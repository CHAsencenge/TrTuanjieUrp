#ifndef CUSTOM_GBUFFER_INCLUDED
#define CUSTOM_GBUFFER_INCLUDED

// Custom Deferred GBuffer encoding/decoding functions.
// Architecture referenced from UE5 DeferredShadingCommon.ush / GBufferHelpers.ush,
// adapted for URP 14.1.0 with custom shading model support.

#include "Packages/com.tr.render/CoreShaderLibrary/Packing.hlsl"

// ---------------------------------------------------------------------------
// Shading Model IDs (must match ShadingModelId.cs)
// ---------------------------------------------------------------------------
#define SHADING_MODEL_DEFAULT_LIT       0
#define SHADING_MODEL_SUBSURFACE        1
#define SHADING_MODEL_CLEAR_COAT        2
#define SHADING_MODEL_TWO_SIDED_FOLIAGE 3
#define SHADING_MODEL_UNLIT             15

// ---------------------------------------------------------------------------
// Material Flags (must match MaterialFlags.cs)
// ---------------------------------------------------------------------------
#define MATERIAL_FLAG_NONE                     0
#define MATERIAL_FLAG_RECEIVE_SHADOWS_OFF       1   // bit 0
#define MATERIAL_FLAG_SPECULAR_HIGHLIGHTS_OFF   2   // bit 1
#define MATERIAL_FLAG_SPECULAR_SETUP            4   // bit 2

// ---------------------------------------------------------------------------
// GBuffer Data Structure
// ---------------------------------------------------------------------------
struct CustomGBufferData
{
    half3 baseColor;
    half3 normalWS;
    half  metallic;
    half  smoothness;
    half  specular;
    half  ao;
    half3 emissive;
    uint  shadingModelId;
    uint  materialFlags;
    half4 customData;  // Per-shading-model data
};

// ---------------------------------------------------------------------------
// Shading Model ID + Material Flags Packing
// Lower 4 bits = ShadingModelId (0-15)
// Upper 4 bits = MaterialFlags
// ---------------------------------------------------------------------------
half PackShadingModelIdAndFlags(uint shadingModelId, uint materialFlags)
{
    uint packed = (shadingModelId & 0x0F) | ((materialFlags & 0x0F) << 4);
    return packed / 255.0;
}

uint UnpackShadingModelId(half packedValue)
{
    uint packed = (uint)(packedValue * 255.0 + 0.5);
    return packed & 0x0F;
}

uint UnpackMaterialFlags(half packedValue)
{
    uint packed = (uint)(packedValue * 255.0 + 0.5);
    return (packed >> 4) & 0x0F;
}

// ---------------------------------------------------------------------------
// Octahedral Normal Encoding/Decoding
// Uses URP core's PackNormalOctQuadEncode which maps [-1,1]^3 -> [-1,1]^2
// We remap to [0,1]^2 for GBuffer storage.
// ---------------------------------------------------------------------------
half2 PackNormalOctahedral(half3 normalWS)
{
    float2 oct = PackNormalOctQuadEncode(normalWS);
    return half2(oct * 0.5 + 0.5); // [-1,1] -> [0,1]
}

half3 UnpackNormalOctahedral(half2 packed)
{
    float2 oct = packed * 2.0 - 1.0; // [0,1] -> [-1,1]
    return half3(UnpackNormalOctQuadEncode(oct));
}

// ---------------------------------------------------------------------------
// GBuffer Encoding (PC: 5 RT layout)
//
// GBuffer0: R8G8B8A8_SRGB  = BaseColor.rgb  + PackedFlags
// GBuffer1: R8G8B8A8_UNorm = Normal.xy(Oct) + Smoothness + Metallic
// GBuffer2: R8G8B8A8_UNorm = Specular + AO  + CustomData.xy
// GBuffer3: B10G11R11_UFloat = Emissive.rgb
// GBuffer4: R8G8B8A8_UNorm = CustomData.zw  + Extra.xy
// ---------------------------------------------------------------------------
void EncodeGBuffer(
    CustomGBufferData data,
    out half4 gbuffer0,
    out half4 gbuffer1,
    out half4 gbuffer2,
    out half3 gbuffer3,
    out half4 gbuffer4)
{
    // GBuffer0: Albedo + packed flags
    gbuffer0.rgb = data.baseColor;
    gbuffer0.a   = PackShadingModelIdAndFlags(data.shadingModelId, data.materialFlags);

    // GBuffer1: Octahedral normal + smoothness + metallic
    half2 packedNormal = PackNormalOctahedral(data.normalWS);
    gbuffer1.rg  = packedNormal;
    gbuffer1.b   = data.smoothness;
    gbuffer1.a   = data.metallic;

    // GBuffer2: Specular + AO + CustomData.xy
    gbuffer2.r   = data.specular;
    gbuffer2.g   = data.ao;
    gbuffer2.b   = data.customData.x;
    gbuffer2.a   = data.customData.y;

    // GBuffer3: Emissive (HDR, B10G11R11)
    gbuffer3     = data.emissive;

    // GBuffer4: CustomData.zw + Reserved
    gbuffer4.r   = data.customData.z;
    gbuffer4.g   = data.customData.w;
    gbuffer4.b   = 0.0;
    gbuffer4.a   = 0.0;
}

// ---------------------------------------------------------------------------
// GBuffer Decoding (PC: 5 RT layout)
// ---------------------------------------------------------------------------
CustomGBufferData DecodeGBuffer(
    half4 gbuffer0,
    half4 gbuffer1,
    half4 gbuffer2,
    half3 gbuffer3,
    half4 gbuffer4)
{
    CustomGBufferData data = (CustomGBufferData)0;

    // GBuffer0
    data.baseColor      = gbuffer0.rgb;
    data.shadingModelId = UnpackShadingModelId(gbuffer0.a);
    data.materialFlags  = UnpackMaterialFlags(gbuffer0.a);

    // GBuffer1
    data.normalWS       = UnpackNormalOctahedral(gbuffer1.rg);
    data.smoothness     = gbuffer1.b;
    data.metallic       = gbuffer1.a;

    // GBuffer2
    data.specular       = gbuffer2.r;
    data.ao             = gbuffer2.g;
    data.customData.x   = gbuffer2.b;
    data.customData.y   = gbuffer2.a;

    // GBuffer3
    data.emissive       = gbuffer3;

    // GBuffer4
    data.customData.z   = gbuffer4.r;
    data.customData.w   = gbuffer4.g;

    return data;
}

// ---------------------------------------------------------------------------
// Mobile GBuffer Encoding (3 RT layout)
//
// GBuffer0: R8G8B8A8_SRGB  = BaseColor.rgb + PackedFlags
// GBuffer1: R8G8B8A8_UNorm = Normal.xy(Oct) + Smoothness + Metallic
// GBuffer2: B10G11R11_UFloat = Emissive/GI (lighting accumulation target)
// ---------------------------------------------------------------------------
void EncodeGBufferMobile(
    CustomGBufferData data,
    out half4 gbuffer0,
    out half4 gbuffer1,
    out half3 gbuffer2)
{
    gbuffer0.rgb = data.baseColor;
    gbuffer0.a   = PackShadingModelIdAndFlags(data.shadingModelId, data.materialFlags);

    half2 packedNormal = PackNormalOctahedral(data.normalWS);
    gbuffer1.rg  = packedNormal;
    gbuffer1.b   = data.smoothness;
    gbuffer1.a   = data.metallic;

    gbuffer2     = data.emissive;
}

CustomGBufferData DecodeGBufferMobile(
    half4 gbuffer0,
    half4 gbuffer1,
    half3 gbuffer2)
{
    CustomGBufferData data = (CustomGBufferData)0;

    data.baseColor      = gbuffer0.rgb;
    data.shadingModelId = UnpackShadingModelId(gbuffer0.a);
    data.materialFlags  = UnpackMaterialFlags(gbuffer0.a);

    data.normalWS       = UnpackNormalOctahedral(gbuffer1.rg);
    data.smoothness     = gbuffer1.b;
    data.metallic       = gbuffer1.a;

    // Mobile uses default specular/AO since they aren't stored in separate RT
    data.specular       = 0.5;
    data.ao             = 1.0;

    data.emissive       = gbuffer2;

    return data;
}

#endif // CUSTOM_GBUFFER_INCLUDED
