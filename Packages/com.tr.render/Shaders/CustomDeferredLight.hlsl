#ifndef CUSTOM_DEFERRED_LIGHT_INCLUDED
#define CUSTOM_DEFERRED_LIGHT_INCLUDED

// Core deferred light evaluation functions.
// Reuses URP's light data structures set by ForwardLights (which runs before our pass).
// Architecture referenced from UE5 DeferredLightingCommon.ush.

#include "Packages/com.tr.render/ShaderLibrary/Core.hlsl"
#include "Packages/com.tr.render/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.tr.render/Shaders/CustomShadingModels.hlsl"

// ---------------------------------------------------------------------------
// World Position Reconstruction from Depth
// Uses the inverse view-projection matrix and screen UV + depth to recover world space position.
// ---------------------------------------------------------------------------
float3 ReconstructWorldPosition(float2 screenUV, float rawDepth)
{
    // Construct clip-space position
    #if UNITY_REVERSED_Z
        float depth = rawDepth;
    #else
        float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, rawDepth);
    #endif

    float4 positionCS = float4(screenUV * 2.0 - 1.0, depth, 1.0);

    // Platform-specific Y flip
    #if UNITY_UV_STARTS_AT_TOP
        positionCS.y = -positionCS.y;
    #endif

    float4 positionWS = mul(UNITY_MATRIX_I_VP, positionCS);
    return positionWS.xyz / positionWS.w;
}

// ---------------------------------------------------------------------------
// Evaluate Main Directional Light
// Reads _MainLightPosition and _MainLightColor set by URP's ForwardLights.
// ---------------------------------------------------------------------------
half3 EvaluateMainLight(
    CustomGBufferData gbufferData,
    CustomBRDFData brdf,
    float3 positionWS,
    half3 viewDirWS)
{
    // Get main light from URP globals
    Light mainLight = GetMainLight();

    // Shadow attenuation (uses URP shadow maps if available)
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS);
    mainLight = GetMainLight(shadowCoord);

    half attenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;

    // Skip unlit shading model (emissive only)
    if (gbufferData.shadingModelId == SHADING_MODEL_UNLIT)
        return half3(0.0, 0.0, 0.0);

    return EvaluateShadingModel(
        gbufferData.shadingModelId,
        brdf,
        gbufferData.normalWS,
        mainLight.direction,
        viewDirWS,
        mainLight.color,
        attenuation,
        gbufferData.customData
    );
}

// ---------------------------------------------------------------------------
// Evaluate Additional Lights (point lights, spot lights)
// Phase 1: Full-screen pass evaluating all additional lights per pixel.
// Phase 4 will add stencil-based light volume culling.
// ---------------------------------------------------------------------------
half3 EvaluateAdditionalLights(
    CustomGBufferData gbufferData,
    CustomBRDFData brdf,
    float3 positionWS,
    half3 viewDirWS)
{
    if (gbufferData.shadingModelId == SHADING_MODEL_UNLIT)
        return half3(0.0, 0.0, 0.0);

    half3 totalLight = half3(0.0, 0.0, 0.0);

    int additionalLightsCount = GetAdditionalLightsCount();
    for (int i = 0; i < additionalLightsCount; i++)
    {
        Light light = GetAdditionalLight(i, positionWS);
        half attenuation = light.distanceAttenuation * light.shadowAttenuation;

        totalLight += EvaluateShadingModel(
            gbufferData.shadingModelId,
            brdf,
            gbufferData.normalWS,
            light.direction,
            viewDirWS,
            light.color,
            attenuation,
            gbufferData.customData
        );
    }

    return totalLight;
}

// ---------------------------------------------------------------------------
// Compute Full Deferred Lighting for a pixel
// Combines main light + additional lights + emissive + ambient
// ---------------------------------------------------------------------------
half3 ComputeDeferredLighting(
    CustomGBufferData gbufferData,
    float3 positionWS,
    half3 viewDirWS)
{
    // Initialize BRDF from GBuffer data
    CustomBRDFData brdf = InitializeCustomBRDFData(
        gbufferData.baseColor,
        gbufferData.metallic,
        gbufferData.smoothness
    );

    half3 finalColor = half3(0.0, 0.0, 0.0);

    // Direct lighting: main light
    finalColor += EvaluateMainLight(gbufferData, brdf, positionWS, viewDirWS);

    // Direct lighting: additional lights
    finalColor += EvaluateAdditionalLights(gbufferData, brdf, positionWS, viewDirWS);

    // Emissive contribution (already stored in GBuffer3)
    finalColor += gbufferData.emissive;

    // Ambient from spherical harmonics (L2), modulated by AO and base color
    half3 ambient = SampleSH(gbufferData.normalWS) * brdf.diffuse * gbufferData.ao;
    finalColor += ambient;

    return finalColor;
}

#endif // CUSTOM_DEFERRED_LIGHT_INCLUDED
