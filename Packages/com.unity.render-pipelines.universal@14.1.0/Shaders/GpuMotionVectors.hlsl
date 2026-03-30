#ifndef UNIVERSAL_GPU_MOTION_VECTORS_INCLUDED
#define UNIVERSAL_GPU_MOTION_VECTORS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

#include "GPUDataDecode.hlsl"
#include "GPUDrivenCommon.hlsl"

Texture2D<uint4> _VisibilityBuffer;

struct Attributes
{
    uint vertexID     : SV_VertexID;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_OUTPUT_STEREO
};

bool EpsilonEqualsFloat4(float4 x, float4 y = float4(0, 0, 0, 0), float epsilon = 1E-5f)
{
    float4 diff = abs(x - y);
    return all(diff <= epsilon);
}

bool EpsilonEqualsFloat2(float2 x, float2 y = float2(0, 0), float epsilon = 1E-5f)
{
    float2 diff = abs(x - y);
    return all(diff <= epsilon);
}

// -------------------------------------
// Vertex
Varyings Vert(Attributes input)
{
    Varyings output;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
    output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
    return output;
}

#if defined(_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
    #define POS_NDC_TYPE float2
#else
    #define POS_NDC_TYPE half2
#endif

// -------------------------------------
// Fragment
void Frag(Varyings input, out float4 outMotionVector : SV_Target0, out float vDepth : SV_Depth)
{
    uint2 uv = input.positionCS.xy;
    vDepth = LoadSceneDepth(uv);
    uint pixelValue = LOAD_TEXTURE2D(_VisibilityBuffer, uv).r;
    uint clusterID = GetVisibleClusterID(pixelValue);
    if (clusterID == 0xFFFFFFFF)
        discard;  // early out if pixel does not have contain VG renderers

    SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
    uint instanceMask = GDRP_ACCESS_PROP(InstanceHeader, uint, mask, survivalCluster.instanceId);
    uint noObjectMotion = ((instanceMask & (1 << 7)) >> 7);
#if defined(HAVE_VFX_MODIFICATION) && !VFX_FEATURE_MOTION_VECTORS
    noObjectMotion = true;
#endif
    if (noObjectMotion)
        discard; // early out if motion vector is disabled

    GPUView view = GetView(survivalCluster.ViewId);
    VGClusterData cluster = LoadCluster(survivalCluster.pageIndex, survivalCluster.clusterIndex);
    float4x4 local2WorldMatrix = MakeInstanceMatrix(GDRP_ACCESS_PROP(InstanceHeader, float3x4, local2World, survivalCluster.instanceId));
    float4x4 preLocal2WorldMatrix = MakeInstanceMatrix(GDRP_ACCESS_PROP(InstanceHeader, float3x4, preLocal2World, survivalCluster.instanceId));
    uint triangleID = GetTriangleID(pixelValue);
    const uint3 triIndices = ReadTriangleIndices(cluster, triangleID);
    const float3 pointLocal0 = DecodePosition(triIndices.x, cluster);
    const float3 pointLocal1 = DecodePosition(triIndices.y, cluster);
    const float3 pointLocal2 = DecodePosition(triIndices.z, cluster);

    float4x4 mvp = mul(view.viewProjectionMatrix, local2WorldMatrix);
    float4 clipPos0 = mul(mvp, float4(pointLocal0, 1.0));
    float4 clipPos1 = mul(mvp, float4(pointLocal1, 1.0));
    float4 clipPos2 = mul(mvp, float4(pointLocal2, 1.0));

    const float2 pixelClip = (input.positionCS.xy) * _ScreenSize.zw * float2(2, 2) + float2(-1, -1);

    Barycentrics barycentrics = CalculateTriangleBarycentrics(pixelClip, clipPos0, clipPos1, clipPos2, _ScreenSize.xy);

    float3 localPosition = barycentrics.UVW.x * pointLocal0
        + barycentrics.UVW.y * pointLocal1
        + barycentrics.UVW.z * pointLocal2;

    // Calculate positions
    float4 worldPos = mul(local2WorldMatrix, float4(localPosition, 1.0f));
    float4 prevPos = mul(preLocal2WorldMatrix, float4(localPosition, 1.0f));

    if (EpsilonEqualsFloat4(worldPos, prevPos)) discard;

    float4 prevClipPos = mul(_PrevViewProjMatrix, prevPos);
    float4 curClipPos = mul(_NonJitteredViewProjMatrix, worldPos);

    POS_NDC_TYPE posNDC = curClipPos.xy * rcp(curClipPos.w);
    POS_NDC_TYPE prevPosNDC = prevClipPos.xy * rcp(prevClipPos.w);

    #if defined(_FOVEATED_RENDERING_NON_UNIFORM_RASTER) && defined(SUPPORTS_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
        // Convert velocity from NDC space (-1..1) to screen UV 0..1 space since FoveatedRendering remap needs that range.
        half2 posUV = RemapFoveatedRenderingResolve(posNDC * 0.5 + 0.5);
        half2 prevPosUV = RemapFoveatedRenderingPrevFrameResolve(prevPosNDC * 0.5 + 0.5);

        // Calculate forward velocity
        float2 motionVector = (posUV - prevPosUV);
        #if UNITY_UV_STARTS_AT_TOP
            motionVector.y = -motionVector.y;
        #endif
        outMotionVector = float4(motionVector.xy, 0.0, 0.0);
    #else
        float2 motionVector = posNDC - prevPosNDC;
        #if UNITY_UV_STARTS_AT_TOP
            motionVector.y = -motionVector.y;
        #endif

        if (EpsilonEqualsFloat2(motionVector)) discard;

        // Convert from Clip space (-1..1) to NDC 0..1 space.
        // Note: ((positionCS * 0.5 + 0.5) - (previousPositionCS * 0.5 + 0.5)) = (motionVector * 0.5)
        outMotionVector = float4(motionVector.xy * 0.5, 0.0, 0.0);
    #endif
}
#endif
