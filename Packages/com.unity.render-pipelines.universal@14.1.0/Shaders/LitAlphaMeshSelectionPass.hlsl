#ifndef UNIVERSAL_LIT_ALPHA_MESH_SELECTION_PASS_INCLUDED
#define UNIVERSAL_LIT_ALPHA_MESH_SELECTION_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

float _PassIndex;

struct AttributesVisibility
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
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

float4 Frag(VaryingsBinning input) : SV_Target0
{
#ifdef GPU_ALPHA_CLIP_ON
    uint materialOffset = input.visibility.y;
    GPUDrivenAlphaClip(input.uv0, materialOffset);
#endif

    float4 output = float4(_PassIndex, _PassIndex, 1.0, 1.0);
    return output;
}

#endif
