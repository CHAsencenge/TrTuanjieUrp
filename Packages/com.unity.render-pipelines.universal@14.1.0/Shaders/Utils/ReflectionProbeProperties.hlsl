#ifndef UNIVERSAL_REFLECTIONPROBE_PROPERTIES_INCLUDE
#define UNIVERSAL_REFLECTIONPROBE_PROPERTIES_INCLUDE

struct ReflectionProbeInfo
{
    uint renderingLayerMask;
    float3 boxMin;
    uint boxProjection_TextureValid_Importance;
    float3 boxMax;
    float blendDistance;
    float3 probePosition;
    float4 scaleOffset;
};

StructuredBuffer<ReflectionProbeInfo> _ReflectionProbeInfoBuffer;
TEXTURE2D(_ReflectionAtlas);
SAMPLER(sampler_ReflectionAtlas);


#endif