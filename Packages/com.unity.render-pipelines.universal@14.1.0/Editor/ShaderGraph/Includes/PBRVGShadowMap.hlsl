
#include "GPUDrivenVertexAnimation.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/VGShadowMapUtilities.hlsl"

struct ShadowCasterAttributes
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
};

#include "Packages/com.unity.render-pipelines.universal/Shaders/VGUtilities.hlsl"

VaryingsBinning vert(ShadowCasterAttributes IN)
{
    VaryingsBinning OUT = (VaryingsBinning)0;
    UNITY_SETUP_INSTANCE_ID(IN);
#ifdef PROCEDURAL_INSTANCING_ON
    // We should apply shadow bias to depth to avoid self-shadow.
    //OUT = GetVaryingsBinningData(IN.instanceID, IN.vertexID);
    OUT = GetVaryingsBinningDataWithShadowBias(IN.instanceID, IN.vertexID);
#else
    OUT.positionCS = float4(0, 0, -1, 1);
    OUT.visibility.x = 23;
    OUT.visibility.x |= 24 << 25;
#endif
    return OUT;
}

void frag(VaryingsBinning IN, out float4 outColor : SV_Target)
{
#if MULTI_VIEW
    if (all(IN.positionCS.xy >= IN.viewPort.xy) && all(IN.positionCS.xy <= IN.viewPort.zw))
#endif
    {
#ifdef GPU_ALPHA_CLIP_ON
        float4x4 local2WorldMatrix;
        float4x4 world2LocalMatrix;
        InstanceSubset instance;
        uint instanceId;
        Varyings varyings = BuildVaryingsTexCoords(IN, local2WorldMatrix, world2LocalMatrix, instance, instanceId);

        uint materialOffset = IN.visibility.y;
        GPUDrivenAlphaClip(varyings, local2WorldMatrix, world2LocalMatrix, instance, instanceId, materialOffset);
#endif
        outColor = 0;
    }
#if MULTI_VIEW
    else
    {
        discard;
    }
#endif
}
