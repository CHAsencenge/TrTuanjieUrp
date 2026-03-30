#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

struct AttributesVisibility
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct FragOut
{
    uint3 visibility : SV_Target0;
};

#include "Packages/com.unity.render-pipelines.universal/Shaders/VGUtilities.hlsl"

VaryingsBinning vert(AttributesVisibility input)
{
    VaryingsBinning output = (VaryingsBinning)0;
    UNITY_SETUP_INSTANCE_ID(input);
    #ifdef PROCEDURAL_INSTANCING_ON
    output = GetVaryingsBinningData(input.instanceID, input.vertexID);
    #else
    output.positionCS = float4(0, 0, -1, 1);
    output.visibility.x = 23;
    output.visibility.x |= 24 << 25;
    #endif
    return output;
}

float4 frag(VaryingsBinning input) : SV_Target0
{
    float4 output = float4(0.0, 0.0, 0.0, 0.0);

#ifdef GPU_ALPHA_CLIP_ON
    float4x4 local2WorldMatrix;
    float4x4 world2LocalMatrix;
    InstanceSubset instance;
    uint instanceId;
    Varyings varyings = BuildVaryingsTexCoords(input, local2WorldMatrix, world2LocalMatrix, instance, instanceId);

    uint materialOffset = input.visibility.y;
    GPUDrivenAlphaClip(varyings, local2WorldMatrix, world2LocalMatrix, instance, instanceId, materialOffset);

    float depth = LoadSceneDepth(input.positionCS.xy);
    if (input.positionCS.z < depth)
    {
        output = float4(0.0, 0.0, 1.0, 1.0);
    }
    else
    {
        output = float4(1.0, 1.0, 1.0, 1.0);
    }
#endif

    return output;
}
