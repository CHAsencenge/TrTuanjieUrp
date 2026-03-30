#ifndef CUSTOM_SHADING_MODELS_INCLUDED
#define CUSTOM_SHADING_MODELS_INCLUDED

// Shading model evaluation dispatch for deferred lighting.
// Architecture referenced from UE5 ShadingModels.ush - per-model BRDF evaluation.
// Phase 2: Subsurface, ClearCoat, TwoSidedFoliage implemented.

#include "Packages/com.tr.render/Shaders/CustomGBuffer.hlsl"
#include "Packages/com.tr.render/Shaders/CustomBRDF.hlsl"

// ---------------------------------------------------------------------------
// DefaultLit: Standard metallic PBR
// ---------------------------------------------------------------------------
half3 EvaluateDefaultLit(
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation)
{
    half NdotL = saturate(dot(normalWS, lightDirWS));
    half3 radiance = lightColor * lightAttenuation * NdotL;
    half3 brdfResult = CustomDirectBRDF(brdf, normalWS, lightDirWS, viewDirWS);
    return brdfResult * radiance;
}

// ---------------------------------------------------------------------------
// Subsurface: Wrapped diffuse + subsurface color transmission
// CustomData usage: xy = SubsurfaceColor.rg, z = SubsurfaceColor.b, w = Opacity
// Referenced from UE5 SubsurfaceProfile shading; simplified to wrap lighting
// (no profile texture lookup - suitable for real-time without precomputed LUTs).
// ---------------------------------------------------------------------------
half3 EvaluateSubsurface(
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation,
    half4 customData)
{
    half3 subsurfaceColor = half3(customData.x, customData.y, customData.z);

    // Standard PBR specular (same as DefaultLit)
    half NdotL = saturate(dot(normalWS, lightDirWS));
    half3 specular = CustomDirectBRDFSpecular(brdf, normalWS, lightDirWS, viewDirWS);

    // Wrapped diffuse: allows light to bleed around the surface (simulates SSS)
    half wrapDiffuse = WrapDiffuse(dot(normalWS, lightDirWS), 0.5);

    // Blend between surface diffuse and subsurface color based on wrap
    half3 diffuseContribution = lerp(brdf.diffuse, subsurfaceColor, saturate(0.5 - NdotL));
    diffuseContribution *= wrapDiffuse;

    half3 radiance = lightColor * lightAttenuation;
    return (diffuseContribution + specular * NdotL) * radiance;
}

// ---------------------------------------------------------------------------
// ClearCoat: Dual-layer material with dielectric coat over base PBR
// CustomData usage: x = ClearCoat strength (0-1), y = ClearCoatRoughness (0-1)
// Referenced from UE5 ClearCoat shading model.
// Top layer: F0=0.04, GGX specular with coat roughness.
// Bottom layer: attenuated by coat Fresnel energy loss.
// ---------------------------------------------------------------------------
half3 EvaluateClearCoat(
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation,
    half4 customData)
{
    half coatStrength  = customData.x;
    half coatRoughness = customData.y;

    half NdotL = saturate(dot(normalWS, lightDirWS));
    half NdotV = saturate(dot(normalWS, viewDirWS));
    half3 radiance = lightColor * lightAttenuation * NdotL;

    // Base layer: standard PBR, attenuated by coat energy absorption
    half2 coatEnergy = ClearCoatEnergyPreservation(coatStrength, NdotV, NdotL);
    half  transmission = coatEnergy.x;

    half3 baseDiffuse  = brdf.diffuse * transmission;
    half3 baseSpecular = CustomDirectBRDFSpecular(brdf, normalWS, lightDirWS, viewDirWS) * transmission;

    // Coat layer: dielectric GGX specular
    half coatSpec = ClearCoatSpecular(coatRoughness, normalWS, lightDirWS, viewDirWS);
    half3 coatContribution = half3(coatSpec * coatStrength, coatSpec * coatStrength, coatSpec * coatStrength);

    return (baseDiffuse + baseSpecular + coatContribution) * radiance;
}

// ---------------------------------------------------------------------------
// TwoSidedFoliage: Standard PBR frontface + wrapped diffuse transmission
// CustomData usage: xyz = BackfaceColor (subsurface transmission color)
// Referenced from UE5 TwoSidedFoliage shading model.
// Adds light transmission through thin surfaces using wrap lighting.
// ---------------------------------------------------------------------------
half3 EvaluateTwoSidedFoliage(
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation,
    half4 customData)
{
    half3 subsurfaceColor = half3(customData.x, customData.y, customData.z);

    // Front face: standard PBR (same as DefaultLit)
    half NdotL = saturate(dot(normalWS, lightDirWS));
    half3 frontRadiance = lightColor * lightAttenuation * NdotL;
    half3 frontLighting = CustomDirectBRDF(brdf, normalWS, lightDirWS, viewDirWS) * frontRadiance;

    // Back face: transmission through foliage
    half3 transmission = FoliageTransmission(normalWS, lightDirWS, viewDirWS, subsurfaceColor);
    half3 backLighting = transmission * lightColor * lightAttenuation;

    return frontLighting + backLighting;
}

// ---------------------------------------------------------------------------
// Unlit: Emissive only, no lighting contribution
// ---------------------------------------------------------------------------
half3 EvaluateUnlit()
{
    return half3(0.0, 0.0, 0.0);
}

// ---------------------------------------------------------------------------
// Shading Model Dispatch
// Routes to the correct evaluation function based on ShadingModelId.
// ---------------------------------------------------------------------------
half3 EvaluateShadingModel(
    uint shadingModelId,
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation,
    half4 customData)
{
    switch (shadingModelId)
    {
        case SHADING_MODEL_DEFAULT_LIT:
            return EvaluateDefaultLit(brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation);

        case SHADING_MODEL_SUBSURFACE:
            return EvaluateSubsurface(brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation, customData);

        case SHADING_MODEL_CLEAR_COAT:
            return EvaluateClearCoat(brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation, customData);

        case SHADING_MODEL_TWO_SIDED_FOLIAGE:
            return EvaluateTwoSidedFoliage(brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation, customData);

        case SHADING_MODEL_UNLIT:
            return EvaluateUnlit();

        default:
            return EvaluateDefaultLit(brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation);
    }
}

// Backward-compatible overload without customData (used by Phase 1 callers)
half3 EvaluateShadingModel(
    uint shadingModelId,
    CustomBRDFData brdf,
    half3 normalWS,
    half3 lightDirWS,
    half3 viewDirWS,
    half3 lightColor,
    half  lightAttenuation)
{
    return EvaluateShadingModel(shadingModelId, brdf, normalWS, lightDirWS, viewDirWS, lightColor, lightAttenuation, half4(0, 0, 0, 0));
}

#endif // CUSTOM_SHADING_MODELS_INCLUDED
