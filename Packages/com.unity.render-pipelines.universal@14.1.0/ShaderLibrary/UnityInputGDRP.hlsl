#ifndef UNIVERSAL_SHADER_VARIABLES_GPUDRIVEN_INCLUDED
#define UNIVERSAL_SHADER_VARIABLES_GPUDRIVEN_INCLUDED

#if defined(UNITY_GPU_DRIVEN_PIPELINE)

#undef unity_LightmapIndex
#undef unity_LightmapST
#undef unity_SHC
#define unity_LightmapIndex     (float)(instance.lightmapOrSH[0] & 0xFFFF)
#define unity_LightmapST        float4(f16tof32(instance.lightmapOrSH[1]&0xFFFF), f16tof32((instance.lightmapOrSH[1]&0xFFFF0000) >> 16), f16tof32(instance.lightmapOrSH[2]&0xFFFF), f16tof32((instance.lightmapOrSH[2]&0xFFFF0000) >> 16))
#define unity_SHC               float4(0, 0, 0, 0)

#ifndef SIMPLE_LIT_GBUFFER_SPLAT

#define unity_SpecCube0_ProbePosition (probeIndex0 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex0].probePosition, (float)(_ReflectionProbeInfoBuffer[probeIndex0].boxProjection_TextureValid_Importance >> (VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS + VG_REFLECTION_PROBE_INFO_TEXTURE_VALID_BITS))) : float4(0.0f, 0.0f, 0.0f, 0.0f))
#define unity_SpecCube0_BoxMin (probeIndex0 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex0].boxMin, 0.0f) : float4(0.0f, 0.0f, 0.0f, 0.0f))
#define unity_SpecCube0_BoxMax (probeIndex0 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex0].boxMax, _ReflectionProbeInfoBuffer[probeIndex0].blendDistance) : float4(0.0f, 0.0f, 0.0f, 0.0f))
#define unity_SpecCube1_ProbePosition (probeIndex1 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex1].probePosition, (float)(_ReflectionProbeInfoBuffer[probeIndex1].boxProjection_TextureValid_Importance >> (VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS + VG_REFLECTION_PROBE_INFO_TEXTURE_VALID_BITS))) : float4(0.0f, 0.0f, 0.0f, 0.0f))
#define unity_SpecCube1_BoxMin (probeIndex1 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex1].boxMin, sign(_ReflectionProbeInfoBuffer[probeIndex0].boxProjection_TextureValid_Importance & ((1u << VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS) - 1u) - _ReflectionProbeInfoBuffer[probeIndex1].boxProjection_TextureValid_Importance & ((1u << VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS) - 1u))) : float4(0.0f, 0.0f, 0.0f, 0.0f))
#define unity_SpecCube1_BoxMax (probeIndex1 != 0xFF ? float4(_ReflectionProbeInfoBuffer[probeIndex1].boxMax, _ReflectionProbeInfoBuffer[probeIndex1].blendDistance) : float4(0.0f, 0.0f, 0.0f, 0.0f))

#endif

#undef UNITY_GDRP_MATERIAL_PAGE_OFFSET_PARAMETER
#undef UNITY_GDRP_MATERIAL_PAGE_OFFSET_ARGUMENT
#undef UNITY_GDRP_INSTANCE_PARAMETER
#undef UNITY_GDRP_INSTANCE_ARGUMENT
#undef UNITY_GDRP_INSTANCE_ID_PARAMETER
#undef UNITY_GDRP_INSTANCE_ID_ARGUMENT
#undef UNITY_GDRP_INSTANCE_ZERO_ARGUMENT
#undef UNITY_GDRP_DDXDDY_PARAMETER
#undef UNITY_GDRP_DDXDDY_ARGUMENT
#undef UNITY_GDRP_MATRIX_M_PARAMETER
#undef UNITY_GDRP_MATRIX_M_ARGUMENT
#undef UNITY_GDRP_MATRIX_M_I_PARAMETER
#undef UNITY_GDRP_MATRIX_M_I_ARGUMENT
#undef UNITY_GDRP_ATTRIBUTE_PARAMETER
#undef UNITY_GDRP_ATTRIBUTE_ARGUMENT
#undef UNITY_GDRP_PROBE_INDEX_PARAMETER
#undef UNITY_GDRP_PROBE_INDEX_ARGUMENT
#undef UNITY_GDRP_PROBE_INDEX_ZERO_ARGUMENT
#define UNITY_GDRP_MATERIAL_PAGE_OFFSET_PARAMETER , uint UNITY_GDRP_MATERIAL_PAGE_OFFSET
#define UNITY_GDRP_MATERIAL_PAGE_OFFSET_ARGUMENT , UNITY_GDRP_MATERIAL_PAGE_OFFSET
#define UNITY_GDRP_INSTANCE_PARAMETER , InstanceSubset instance
#define UNITY_GDRP_INSTANCE_ARGUMENT , instance
#define UNITY_GDRP_INSTANCE_ID_PARAMETER , uint instanceID
#define UNITY_GDRP_INSTANCE_ID_ARGUMENT , instanceID
#define UNITY_GDRP_INSTANCE_ZERO_ARGUMENT , (InstanceSubset)0
#define UNITY_GDRP_DDXDDY_PARAMETER , float2 ddx, float2 ddy
#define UNITY_GDRP_DDXDDY_ARGUMENT , ddx, ddy
#define UNITY_GDRP_MATRIX_M_PARAMETER , float4x4 local2WorldMatrix
#define UNITY_GDRP_MATRIX_M_ARGUMENT , local2WorldMatrix
#define UNITY_GDRP_MATRIX_M_I_PARAMETER , float4x4 world2LocalMatrix
#define UNITY_GDRP_MATRIX_M_I_ARGUMENT , world2LocalMatrix
#define UNITY_GDRP_ATTRIBUTE_PARAMETER , PixelAttribute attribute
#define UNITY_GDRP_ATTRIBUTE_ARGUMENT , attribute
#define UNITY_GDRP_PROBE_INDEX_PARAMETER , uint probeIndex0, uint probeIndex1
#define UNITY_GDRP_PROBE_INDEX_ARGUMENT , probeIndex0, probeIndex1
#define UNITY_GDRP_PROBE_INDEX_ZERO_ARGUMENT , 0u, 0u

#define UNITY_GDRP_PROP_INDEX(Name) _Offset##Name
#define UNITY_GDRP_NEXT_INDEX(Name) UNITY_GDRP_PROP_INDEX(Name) + 1
#undef UNITY_DEFINE_PROP
#define UNITY_DEFINE_PROP(Type, Name, Index) static int _Offset##Name = Index;


#define UNITY_GDRP_MATERIAL_PAGE_OFFSET materialOffset
#define UNITY_GDRP_MATERIAL_LOAD(Type, MaterialOffset, Offset) LoadMaterialBuffer_##Type(MaterialOffset, Offset)
#define UNITY_GDRP_MATERIAL_LOAD_ARRAY(Type, MaterialOffset, Offset, Index) LoadMaterialBuffer_##Type##Array(MaterialOffset, Offset, Index)
#define UNITY_GDRP_PROP_OFFSET(Name) _Offset##Name*4

#define UNITY_GDRP_PROP_START (4)

//ByteAddressBuffer _MaterialBuffer;
float4 LoadMaterialBuffer_float4(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return (float4)0.0f;

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    return asfloat(_MaterialBuffer.Load4(materialOffset + address));
}

float4 LoadMaterialBuffer_float4Array(uint materialOffset, uint indexOffset, uint arrayIndex)
{
    if (materialOffset == ~0u)
        return (float4) 0.0f;

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    return asfloat(_MaterialBuffer.Load4(materialOffset + address + arrayIndex * 16));
}

half4 LoadMaterialBuffer_min16float4(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return half4(0.0f, 0.0f, 0.0f, 0.0f);

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    uint2 value = _MaterialBuffer.Load2(materialOffset + address);
    return half4(f16tof32(value.x & 0xFFFF), f16tof32(value.x >> 16), f16tof32(value.y & 0xFFFF), f16tof32(value.y >> 16));
}

half4 LoadMaterialBuffer_half4(uint materialOffset, uint indexOffset)
{
    return LoadMaterialBuffer_float4(materialOffset, indexOffset);
}

float3 LoadMaterialBuffer_float3(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return (float3) 0.0f;

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    return asfloat(_MaterialBuffer.Load3(materialOffset + address));
}

half3 LoadMaterialBuffer_min16float3(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return half3(0.0f, 0.0f, 0.0f);

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    uint2 value = _MaterialBuffer.Load2(materialOffset + address & ~3u);
    float decodeValue[4];
    decodeValue[0] = f16tof32(value.x & 0xFFFF);
    decodeValue[1] = f16tof32(value.x >> 16);
    decodeValue[2] = f16tof32(value.y & 0xFFFF);
    decodeValue[3] = f16tof32(value.y >> 16);
    uint startIndex = (address & 2) >> 1;
    return half3(decodeValue[startIndex], decodeValue[startIndex + 1], decodeValue[startIndex + 2]);
}

float2 LoadMaterialBuffer_float2(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return float2(0.0f, 0.0f);

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    return asfloat(_MaterialBuffer.Load2(materialOffset + address));
}

half2 LoadMaterialBuffer_min16float2(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return float2(0.0f, 0.0f);

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    uint value = _MaterialBuffer.Load(materialOffset + address);
    return half2(f16tof32(value & 0xFFFF), f16tof32(value >> 16));
}

float LoadMaterialBuffer_float(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return 0.0f;

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    return asfloat(_MaterialBuffer.Load(materialOffset + address));
}

half LoadMaterialBuffer_min16float(uint materialOffset, uint indexOffset)
{
    if (materialOffset == ~0u)
        return 0.0f;

    indexOffset += UNITY_GDRP_PROP_START;
    uint address = _MaterialBuffer.Load(materialOffset + indexOffset);
    bool aligned = (address % 4 == 0);
    half res;
    if (aligned)
        res = f16tof32(_MaterialBuffer.Load(materialOffset + address) & 0xFFFF);
    else
        res = f16tof32(_MaterialBuffer.Load(materialOffset + (address & ~3u)) >> 16);

    return res;
}

half LoadMaterialBuffer_half(uint materialOffset, uint indexOffset)
{
    return LoadMaterialBuffer_float(materialOffset, indexOffset);
}

#endif  // UNITY_GPU_DRIVEN_PIPELINE

#endif // UNIVERSAL_SHADER_VARIABLES_GPUDRIVEN_INCLUDED
