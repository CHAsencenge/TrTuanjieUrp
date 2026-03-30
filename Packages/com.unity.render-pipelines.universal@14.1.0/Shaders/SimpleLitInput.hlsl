#ifndef UNIVERSAL_SIMPLE_LIT_INPUT_INCLUDED
#define UNIVERSAL_SIMPLE_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

CBUFFER_START(UnityPerMaterial)
UNITY_DEFINE_PROP(float4, _BaseMap_ST, 0)
UNITY_DEFINE_PROP(half4, _BaseColor, UNITY_GDRP_NEXT_INDEX(_BaseMap_ST))
UNITY_DEFINE_PROP(half4, _SpecColor, UNITY_GDRP_NEXT_INDEX(_BaseColor))
UNITY_DEFINE_PROP(half4, _EmissionColor, UNITY_GDRP_NEXT_INDEX(_SpecColor))
UNITY_DEFINE_PROP(half, _Cutoff, UNITY_GDRP_NEXT_INDEX(_EmissionColor))
UNITY_DEFINE_PROP(half, _Surface, UNITY_GDRP_NEXT_INDEX(_Cutoff))
CBUFFER_END

#ifdef UNITY_DOTS_INSTANCING_ENABLED
UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
    UNITY_DOTS_INSTANCED_PROP(float4, _BaseColor)
    UNITY_DOTS_INSTANCED_PROP(float4, _SpecColor)
    UNITY_DOTS_INSTANCED_PROP(float4, _EmissionColor)
    UNITY_DOTS_INSTANCED_PROP(float , _Cutoff)
    UNITY_DOTS_INSTANCED_PROP(float , _Surface)
UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

static float4 unity_DOTS_Sampled_BaseColor;
static float4 unity_DOTS_Sampled_SpecColor;
static float4 unity_DOTS_Sampled_EmissionColor;
static float  unity_DOTS_Sampled_Cutoff;
static float  unity_DOTS_Sampled_Surface;

void SetupDOTSSimpleLitMaterialPropertyCaches()
{
    unity_DOTS_Sampled_BaseColor     = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4 , _BaseColor);
    unity_DOTS_Sampled_SpecColor     = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4 , _SpecColor);
    unity_DOTS_Sampled_EmissionColor = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4 , _EmissionColor);
    unity_DOTS_Sampled_Cutoff        = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float  , _Cutoff);
    unity_DOTS_Sampled_Surface       = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float  , _Surface);
}

#undef UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES
#define UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES() SetupDOTSSimpleLitMaterialPropertyCaches()

#define _BaseColor          unity_DOTS_Sampled_BaseColor
#define _SpecColor          unity_DOTS_Sampled_SpecColor
#define _EmissionColor      unity_DOTS_Sampled_EmissionColor
#define _Cutoff             unity_DOTS_Sampled_Cutoff
#define _Surface            unity_DOTS_Sampled_Surface

#endif

#ifdef UNITY_GPU_DRIVEN_PIPELINE
#if defined(SHADER_API_MOBILE) && defined(SHADER_API_METAL) || defined(UNITY_UNIFIED_SHADER_PRECISION_MODEL)
#define _BaseMap_ST             UNITY_GDRP_MATERIAL_LOAD(float4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_BaseMap_ST))
#define _BaseColor              UNITY_GDRP_MATERIAL_LOAD(half4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_BaseColor))
#define _SpecColor              UNITY_GDRP_MATERIAL_LOAD(half4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_SpecColor))
#define _EmissionColor          UNITY_GDRP_MATERIAL_LOAD(half4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_EmissionColor))
#define _Cutoff                 UNITY_GDRP_MATERIAL_LOAD(half , UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_Cutoff))
#define _Surface                UNITY_GDRP_MATERIAL_LOAD(half , UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_Surface))
#else
#define _BaseMap_ST             UNITY_GDRP_MATERIAL_LOAD(float4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_BaseMap_ST))
#define _BaseColor              UNITY_GDRP_MATERIAL_LOAD(float4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_BaseColor))
#define _SpecColor              UNITY_GDRP_MATERIAL_LOAD(float4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_SpecColor))
#define _EmissionColor          UNITY_GDRP_MATERIAL_LOAD(float4, UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_EmissionColor))
#define _Cutoff                 UNITY_GDRP_MATERIAL_LOAD(float , UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_Cutoff))
#define _Surface                UNITY_GDRP_MATERIAL_LOAD(float , UNITY_GDRP_MATERIAL_PAGE_OFFSET, UNITY_GDRP_PROP_OFFSET(_Surface))
#endif
#endif //UNITY_GPU_DRIVEN_PIPELINE

TEXTURE2D(_SpecGlossMap);       SAMPLER(sampler_SpecGlossMap);

half4 SampleSpecularSmoothness(float2 uv, half alpha, half4 specColor,
    TEXTURE2D_PARAM(specMap, sampler_specMap)
    UNITY_GDRP_DDXDDY_PARAMETER)
{
    half4 specularSmoothness = half4(0, 0, 0, 1);
#ifdef _SPECGLOSSMAP
#ifdef UNITY_GPU_DRIVEN_PIPELINE
    specularSmoothness = SAMPLE_TEXTURE2D_GRAD(specMap, sampler_specMap, uv, ddx, ddy) * specColor;
#else
    specularSmoothness = SAMPLE_TEXTURE2D(specMap, sampler_specMap, uv) * specColor;
#endif
#elif defined(_SPECULAR_COLOR)
    specularSmoothness = specColor;
#endif

#ifdef _GLOSSINESS_FROM_BASE_ALPHA
    specularSmoothness.a = alpha;
#endif

    return specularSmoothness;
}

inline void InitializeSimpleLitSurfaceData(float2 uv, out SurfaceData outSurfaceData
    UNITY_GDRP_MATERIAL_PAGE_OFFSET_PARAMETER
    UNITY_GDRP_DDXDDY_PARAMETER)
{
#ifdef UNITY_GPU_DRIVEN_PIPELINE
    float4 ddxddy = float4(ddx, ddy);
    ddx *= _BaseMap_ST.xy;
    ddy *= _BaseMap_ST.xy;
#endif

    outSurfaceData = (SurfaceData)0;

    half4 albedoAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap) UNITY_GDRP_DDXDDY_ARGUMENT);
    outSurfaceData.alpha = albedoAlpha.a * _BaseColor.a;
    outSurfaceData.alpha = AlphaDiscard(outSurfaceData.alpha, _Cutoff);

    outSurfaceData.albedo = albedoAlpha.rgb * _BaseColor.rgb;
    outSurfaceData.albedo = AlphaModulate(outSurfaceData.albedo, outSurfaceData.alpha);

    half4 specularSmoothness = SampleSpecularSmoothness(uv, outSurfaceData.alpha, _SpecColor, TEXTURE2D_ARGS(_SpecGlossMap, sampler_SpecGlossMap) UNITY_GDRP_DDXDDY_ARGUMENT);
    outSurfaceData.metallic = 0.0; // unused
    outSurfaceData.specular = specularSmoothness.rgb;
    outSurfaceData.smoothness = specularSmoothness.a;
    outSurfaceData.normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap) UNITY_GDRP_DDXDDY_ARGUMENT);
    outSurfaceData.occlusion = 1.0;
    outSurfaceData.emission = SampleEmission(uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap) UNITY_GDRP_DDXDDY_ARGUMENT);
}

#ifdef UNITY_GPU_DRIVEN_PIPELINE
void GPUDrivenAlphaClip(float2 uv, uint materialOffset)
{
    uv = uv * _BaseMap_ST.xy + _BaseMap_ST.zw;
    float alphaTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a;
    float alphaValue = lerp(0, 1, alphaTex);
    alphaValue = AlphaDiscard(alphaValue, _Cutoff);
    clip(alphaValue - _Cutoff);
}
#endif

#endif
