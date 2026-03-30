#ifndef CUSTOM_DEFERRED_LIT_INPUT_INCLUDED
#define CUSTOM_DEFERRED_LIT_INPUT_INCLUDED

// Material input structure for the custom deferred GBuffer pass.
// Defines properties and sampling functions for surface attributes.
// Note: SurfaceInput.hlsl already declares _BaseMap, _BumpMap, _EmissionMap,
// and their samplers, as well as SampleNormal() and SampleEmission() functions.
// We only declare additional textures and use prefixed function names to avoid conflicts.

#include "Packages/com.tr.render/ShaderLibrary/Core.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/SurfaceInput.hlsl"

// ---------------------------------------------------------------------------
// Material Property Block (CBUFFER)
// ---------------------------------------------------------------------------
CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    half4  _BaseColor;
    half   _Metallic;
    half   _Smoothness;
    half   _Specular;
    half   _OcclusionStrength;
    half   _BumpScale;
    half   _Cutoff;
    half3  _EmissionColor;
    float  _ShadingModelId;
    float  _MaterialFlags;
    half4  _CustomData;
CBUFFER_END

// ---------------------------------------------------------------------------
// Additional Textures (not declared by SurfaceInput.hlsl)
// ---------------------------------------------------------------------------
TEXTURE2D(_MetallicGlossMap);   SAMPLER(sampler_MetallicGlossMap);
TEXTURE2D(_OcclusionMap);       SAMPLER(sampler_OcclusionMap);

// ---------------------------------------------------------------------------
// Surface Data for GBuffer writing
// ---------------------------------------------------------------------------
struct CustomSurfaceData
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
    half4 customData;
};

// ---------------------------------------------------------------------------
// Surface Sampling (prefixed to avoid conflicts with SurfaceInput.hlsl)
// ---------------------------------------------------------------------------
half4 CustomSampleBaseColor(float2 uv)
{
    return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
}

half3 CustomSampleNormalWS(float2 uv, half3 normalWS, half4 tangentWS)
{
#ifdef _NORMALMAP
    half4 normalSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv);
    half3 normalTS = UnpackNormalScale(normalSample, _BumpScale);

    // Construct TBN matrix
    float sgn = tangentWS.w * GetOddNegativeScale();
    half3 bitangent = sgn * cross(normalWS, tangentWS.xyz);
    half3x3 tbn = half3x3(tangentWS.xyz, bitangent, normalWS);

    return normalize(mul(normalTS, tbn));
#else
    return normalize(normalWS);
#endif
}

half2 CustomSampleMetallicGloss(float2 uv)
{
#ifdef _METALLICGLOSSMAP
    half4 mg = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, uv);
    return half2(mg.r * _Metallic, mg.a * _Smoothness);
#else
    return half2(_Metallic, _Smoothness);
#endif
}

half CustomSampleOcclusion(float2 uv)
{
#ifdef _OCCLUSIONMAP
    half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, uv).g;
    return lerp(1.0, occ, _OcclusionStrength);
#else
    return 1.0;
#endif
}

half3 CustomSampleEmission(float2 uv)
{
#ifdef _EMISSION
    return SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionColor;
#else
    return _EmissionColor;
#endif
}

// ---------------------------------------------------------------------------
// Initialize full surface data from material properties and texture samples
// ---------------------------------------------------------------------------
CustomSurfaceData InitializeSurfaceData(float2 uv, half3 normalWS, half4 tangentWS)
{
    CustomSurfaceData surface = (CustomSurfaceData)0;

    half4 baseColor = CustomSampleBaseColor(uv);
    surface.baseColor = baseColor.rgb;

    surface.normalWS = CustomSampleNormalWS(uv, normalWS, tangentWS);

    half2 metallicGloss = CustomSampleMetallicGloss(uv);
    surface.metallic   = metallicGloss.x;
    surface.smoothness = metallicGloss.y;

    surface.specular = _Specular;
    surface.ao       = CustomSampleOcclusion(uv);
    surface.emissive = CustomSampleEmission(uv);

    surface.shadingModelId = (uint)_ShadingModelId;
    surface.materialFlags  = (uint)_MaterialFlags;
    surface.customData     = _CustomData;

    return surface;
}

#endif // CUSTOM_DEFERRED_LIT_INPUT_INCLUDED
