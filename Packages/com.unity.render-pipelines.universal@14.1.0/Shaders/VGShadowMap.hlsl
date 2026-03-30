#ifndef UNIVERSAL_VG_SHADOW_MAP_INCLUDED
#define UNIVERSAL_VG_SHADOW_MAP_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/Shaders/VGShadowMapUtilities.hlsl"

struct ShadowCasterAttributes
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
};

VaryingsBinning Vert(ShadowCasterAttributes IN)
{
    VaryingsBinning OUT = (VaryingsBinning)0;
    UNITY_SETUP_INSTANCE_ID(IN);
#ifdef PROCEDURAL_INSTANCING_ON
    // We should apply shadow bias to depth to avoid self-shadow.
    //OUT = GetVaryingsBinningData(IN.instanceID, IN.vertexID);
    OUT = GetVaryingsBinningDataWithShadowBias(IN.instanceID, IN.vertexID);
#else
    OUT.positionCS = float4(0, 0, -1, 1);
#endif
    return OUT;
}

void Frag(VaryingsBinning IN, out float4 outColor : SV_Target)
{
    outColor = (float4)0;
#if MULTI_VIEW
    if (all(IN.positionCS.xy >= IN.viewPort.xy) && all(IN.positionCS.xy <= IN.viewPort.zw))
#endif
    {
#ifdef GPU_ALPHA_CLIP_ON
        GPUDrivenAlphaClip(IN.uv0, IN.visibility.y);
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

#endif
