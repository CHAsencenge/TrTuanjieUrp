struct AttributesVisibility
{
    uint vertexID : SV_VertexID;
    DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct FragOut
{
    uint2 visibility : SV_Target0;
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

FragOut frag(VaryingsBinning input)
{
    FragOut output;

#ifdef GPU_ALPHA_CLIP_ON
    output.visibility.r = input.visibility.x;

    float4x4 local2WorldMatrix;
    float4x4 world2LocalMatrix;
    InstanceSubset instance;
    uint instanceId;
    Varyings varyings = BuildVaryingsTexCoords(input, local2WorldMatrix, world2LocalMatrix, instance, instanceId);

    uint materialOffset = input.visibility.y;
    GPUDrivenAlphaClip(varyings, local2WorldMatrix, world2LocalMatrix, instance, instanceId, materialOffset);
#endif

    return output;
}
