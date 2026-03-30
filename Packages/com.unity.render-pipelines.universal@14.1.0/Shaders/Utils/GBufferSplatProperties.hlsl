#ifndef UNIVERSAL_GBUFFERSPLAT_PROPERTIES_INCLUDE
#define UNIVERSAL_GBUFFERSPLAT_PROPERTIES_INCLUDE

CBUFFER_START(GBufferSplatProperty)
    float4 _TileSizeAndTargetSize;
    float _CurrentMaterialID;
    float4 _ReflectionPaddingData;
CBUFFER_END


StructuredBuffer<uint4> _MaterialRangeBuffer;

struct AttributesVG
{
    uint vertexID : SV_VertexID;
    uint instanceID : SV_InstanceID;
};

struct VaryingsVG
{
    float4 positionCS : SV_POSITION;
    float2 texcoord : TEXCOORD0;
    DEFAULT_UNITY_VERTEX_OUTPUT_STEREO
};

#endif