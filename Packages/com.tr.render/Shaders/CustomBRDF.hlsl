#ifndef CUSTOM_BRDF_INCLUDED
#define CUSTOM_BRDF_INCLUDED

// Custom BRDF evaluation for deferred lighting.
// Extends URP's BRDF.hlsl with a unified entry point for multiple shading models.
// Architecture referenced from UE5 ShadingModels.ush.

#include "Packages/com.tr.render/ShaderLibrary/BRDF.hlsl"

// ---------------------------------------------------------------------------
// Custom BRDF Data (extends URP BRDFData with deferred-specific fields)
// ---------------------------------------------------------------------------
struct CustomBRDFData
{
    half3 albedo;
    half3 diffuse;
    half3 specular;
    half  reflectivity;
    half  perceptualRoughness;
    half  roughness;
    half  roughness2;
    half  grazingTerm;
    half  normalizationTerm;
    half  roughness2MinusOne;
};

// ---------------------------------------------------------------------------
// Initialize CustomBRDFData from GBuffer decoded values
// Uses metallic workflow by default.
// ---------------------------------------------------------------------------
CustomBRDFData InitializeCustomBRDFData(half3 baseColor, half metallic, half smoothness)
{
    CustomBRDFData brdf = (CustomBRDFData)0;

    half oneMinusReflectivity = OneMinusReflectivityMetallic(metallic);
    half reflectivity = half(1.0) - oneMinusReflectivity;

    brdf.albedo    = baseColor;
    brdf.diffuse   = baseColor * oneMinusReflectivity;
    brdf.specular  = lerp(kDieletricSpec.rgb, baseColor, metallic);
    brdf.reflectivity = reflectivity;

    brdf.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    brdf.roughness  = max(PerceptualRoughnessToRoughness(brdf.perceptualRoughness), HALF_MIN_SQRT);
    brdf.roughness2 = max(brdf.roughness * brdf.roughness, HALF_MIN);
    brdf.grazingTerm = saturate(smoothness + reflectivity);
    brdf.normalizationTerm = brdf.roughness * half(4.0) + half(2.0);
    brdf.roughness2MinusOne = brdf.roughness2 - half(1.0);

    return brdf;
}

// ---------------------------------------------------------------------------
// GGX Specular BRDF (same as URP DirectBRDFSpecular but using our struct)
// D * V * F approximation using Minimalist CookTorrance
// ---------------------------------------------------------------------------
half3 CustomDirectBRDFSpecular(CustomBRDFData brdf, half3 normalWS, half3 lightDirWS, half3 viewDirWS)
{
    float3 halfDir = SafeNormalize(float3(lightDirWS) + float3(viewDirWS));

    float NoH = saturate(dot(normalWS, halfDir));
    half  LoH = half(saturate(dot(lightDirWS, halfDir)));

    // GGX Distribution * Visibility combined
    float d = NoH * NoH * brdf.roughness2MinusOne + 1.00001f;
    half  LoH2 = LoH * LoH;
    half  specularTerm = brdf.roughness2 / ((d * d) * max(half(0.1), LoH2) * brdf.normalizationTerm);

    // Clamp for half-precision safety
#if defined(SHADER_API_MOBILE) || defined(SHADER_API_SWITCH)
    specularTerm = specularTerm - HALF_MIN;
    specularTerm = clamp(specularTerm, 0.0, 100.0);
#endif

    return half3(specularTerm * brdf.specular);
}

// ---------------------------------------------------------------------------
// Full Direct BRDF: Diffuse + Specular
// ---------------------------------------------------------------------------
half3 CustomDirectBRDF(CustomBRDFData brdf, half3 normalWS, half3 lightDirWS, half3 viewDirWS)
{
    half3 specularComponent = CustomDirectBRDFSpecular(brdf, normalWS, lightDirWS, viewDirWS);
    return brdf.diffuse + specularComponent;
}

// ---------------------------------------------------------------------------
// Environment BRDF for indirect lighting (simplified Fresnel)
// ---------------------------------------------------------------------------
half3 CustomEnvironmentBRDF(CustomBRDFData brdf, half3 normalWS, half3 viewDirWS, half3 indirectDiffuse, half3 indirectSpecular)
{
    half NoV = saturate(dot(normalWS, viewDirWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 diffuse  = indirectDiffuse * brdf.diffuse;
    half3 specular = indirectSpecular * lerp(brdf.specular, half3(brdf.grazingTerm, brdf.grazingTerm, brdf.grazingTerm), fresnelTerm);

    return diffuse + specular;
}

// ---------------------------------------------------------------------------
// Clear Coat Helpers
// Referenced from UE5 ShadingModels.ush ClearCoat evaluation.
// Top layer uses F0 = 0.04 (polyurethane IOR ~1.5).
// ---------------------------------------------------------------------------

// Schlick Fresnel with F0 = 0.04 for dielectric clear coat
half ClearCoatFresnel(half VdotH)
{
    half Fc = Pow4(1.0 - VdotH); // Pow4 approximation of Pow5 for perf
    return 0.04 + 0.96 * Fc;     // F0=0.04, F90=1.0
}

// GGX specular for the clear coat layer (simplified single-lobe)
half ClearCoatSpecular(half roughness, half3 normalWS, half3 lightDirWS, half3 viewDirWS)
{
    half coatRoughness = max(roughness, 0.02); // Minimum roughness to avoid singularity
    half coatRoughness2 = coatRoughness * coatRoughness;

    float3 halfDir = SafeNormalize(float3(lightDirWS) + float3(viewDirWS));
    float NoH = saturate(dot(normalWS, halfDir));
    half  LoH = half(saturate(dot(lightDirWS, halfDir)));

    // GGX NDF
    float d = NoH * NoH * (coatRoughness2 - 1.0) + 1.00001f;
    half  D = coatRoughness2 / (d * d);

    // Fresnel
    half F = ClearCoatFresnel(LoH);

    // Simplified Vis (Kelemen approximation)
    half Vis = 0.25 / max(LoH * LoH, 0.001);

    return D * F * Vis;
}

// Energy absorbed by the clear coat layer (transmitted to base)
// Returns (1 - F)^2 approximation for both entry and exit through coat
half2 ClearCoatEnergyPreservation(half coatStrength, half NoV, half NoL)
{
    half Fv = ClearCoatFresnel(NoV);
    half Fl = ClearCoatFresnel(NoL);
    half transmission = (1.0 - Fv * coatStrength) * (1.0 - Fl * coatStrength);
    return half2(transmission, Fv * coatStrength);
}

// ---------------------------------------------------------------------------
// Subsurface Helpers
// Referenced from UE5 ShadingModels.ush Subsurface evaluation.
// Uses wrapped diffuse lighting for simplified subsurface scattering.
// ---------------------------------------------------------------------------

// Wrap lighting: allows light to partially illuminate the backside
// wrapFactor: 0 = standard Lambert, 1 = fully wrapped hemisphere
half WrapDiffuse(half NdotL, half wrapFactor)
{
    return saturate((NdotL + wrapFactor) / ((1.0 + wrapFactor) * (1.0 + wrapFactor)));
}

// ---------------------------------------------------------------------------
// Two-Sided Foliage Helpers
// Referenced from UE5 ShadingModels.ush TwoSidedFoliage evaluation.
// Wrapped diffuse transmission with view-dependent scattering.
// ---------------------------------------------------------------------------

// Transmission term for thin foliage
// Uses wrapped diffuse on backface + view-dependent scattering
half3 FoliageTransmission(half3 normalWS, half3 lightDirWS, half3 viewDirWS, half3 subsurfaceColor)
{
    // Wrap lighting for transmission (inverted normal)
    half wrapNoL = saturate((-dot(normalWS, lightDirWS) + 0.5) / 2.25);

    // View-dependent scattering: stronger when looking toward the light through foliage
    half VdotL = saturate(dot(viewDirWS, -lightDirWS));
    half scatter = Pow4(VdotL) * 2.0; // Approximate forward scattering phase function

    return subsurfaceColor * (wrapNoL + wrapNoL * scatter);
}

#endif // CUSTOM_BRDF_INCLUDED
