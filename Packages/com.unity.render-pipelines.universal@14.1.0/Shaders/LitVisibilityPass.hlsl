#ifndef UNIVERSAL_LIT_VISIBILITI_PASS_INCLUDED
#define UNIVERSAL_LIT_VISIBILITI_PASS_INCLUDED

struct AttributesVisibility
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct FragOut
{
    uint visibility : SV_Target0;
};

#include "Packages/com.unity.render-pipelines.universal/Shaders/VGUtilities.hlsl"

VaryingsBinning Vert(AttributesVisibility input)
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

FragOut Frag(VaryingsBinning input)
{

    FragOut output;

#ifdef GPU_ALPHA_CLIP_ON
    output.visibility.r = input.visibility.x;
    uint materialOffset = input.visibility.y;
    GPUDrivenAlphaClip(input.uv0, materialOffset);
#endif

    return output;
}

#endif
