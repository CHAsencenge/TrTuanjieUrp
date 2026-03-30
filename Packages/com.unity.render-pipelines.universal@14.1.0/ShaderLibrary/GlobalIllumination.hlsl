
#ifndef UNIVERSAL_GLOBAL_ILLUMINATION_INCLUDED
#define UNIVERSAL_GLOBAL_ILLUMINATION_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "GPUDrivenLightProbes.hlsl"



#if USE_CLUSTERED_LIGHTING
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
#endif

// If lightmap is not defined than we evaluate GI (ambient + probes) from SH

// We need pass ambient data from CPU to GPU for VG. In HDRP, this is a buffer
// for the reason that it will be generated in compute shader. But in URP, we
// just set it as a float4 array set in C#.
real4 _AmbientProbeData[7];

// Renamed -> LIGHTMAP_SHADOW_MIXING
#if !defined(_MIXED_LIGHTING_SUBTRACTIVE) && defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK)
    #define _MIXED_LIGHTING_SUBTRACTIVE
#endif

// Samples SH L0, L1 and L2 terms
half3 SampleSH(half3 normalWS)
{
    // LPPV is not supported in Ligthweight Pipeline
    real4 SHCoefficients[7];
    SHCoefficients[0] = unity_SHAr;
    SHCoefficients[1] = unity_SHAg;
    SHCoefficients[2] = unity_SHAb;
    SHCoefficients[3] = unity_SHBr;
    SHCoefficients[4] = unity_SHBg;
    SHCoefficients[5] = unity_SHBb;
    SHCoefficients[6] = unity_SHC;

    return max(half3(0, 0, 0), SampleSH9(SHCoefficients, normalWS));
}

#if SUPPORTS_GPU_DRIVEN_LIGHTPROBE
// For GPU Driven LightProbes, we will get SHCoefficients on pixel shader, so just use it.
half3 SampleSH(real4 SHCoefficients[7], half3 normalWS)
{
    return max(half3(0, 0, 0), SampleSH9(SHCoefficients, normalWS));
}

half3 EvaluateAmbientProbe(float3 normalWS)
{
    return SampleSH(_AmbientProbeData, normalWS);
}

half3 EvaluateLightProbe(half3 normalWS, int tetIndex, float4 weights)
{
    if (tetIndex < 0 || tetIndex >= _TetrahedronCount)
        return half3(0, 0, 0);

    SphericalHarmonicsL2 coefficients;
    ZERO_INITIALIZE(SphericalHarmonicsL2, coefficients);

    CalculateLightProbesCoefficients(tetIndex, weights, coefficients);

    real4 SHCoefficients[7];
    GetShaderConstantsFromNormalizedSH(coefficients, SHCoefficients);

    half3 res = SampleSH(SHCoefficients, normalWS);

    if (AnyIsNaN(res))
        res.xyz = 0.0f;

    return res;
}

// To reduce the same process of calculating tet index, we should put
// SampleSHVertex, SampleSHPixel and SampleShadowMask together. And
// those calculations are only finished in frag stage.
half3 SampleSHAndShadowMask(float3 positionWS,
    half3 normalWS,
    inout half4 shadowMask
    UNITY_GDRP_INSTANCE_PARAMETER)
{
    // Attention: If there's any return in the if-condition part, the rest return must be put into the else-condition part,
    // or we will get a warning about 'use of potentially uninitialized variable'
#ifdef UNITY_GPU_DRIVEN_PIPELINE
    if (_LightProbeOutsideHullStrategy != 0
        && COEFF_TYPE(instance.lightmapOrSH[0]) == BLEND_COEFF_TYPE
        && IS_OUTSIDE(instance.lightmapOrSH[0]) == RENDERER_IS_OUTSIDE)
    {
        // When we use ambient probe, we shall not use occlusion probe.
        shadowMask = float4(1, 1, 1, 1);
        return EvaluateAmbientProbe(normalWS);
    }
    else
#endif
    {
        // If it is None or Ambient CoeffType, the tetIndex will not be changed. So we can
        // simply think that tetIndex is -1 means no Occlusion Probe sample.
        int tetIndex = -1;
        float4 weights = (float4)0;

        // Init tetIndex and weights
#ifdef UNITY_GPU_DRIVEN_PIPELINE
        uint coeffType = COEFF_TYPE(instance.lightmapOrSH[0]);
        if (coeffType > AMBIENT_COEFF_TYPE)
        {
            if (coeffType == PERPIXEL_COEFF_TYPE)
                weights = GetLightProbeInterpolationWeight(positionWS, tetIndex, true);
            else
            {
                float3 center = float3(asfloat(instance.lightmapOrSH[1]), asfloat(instance.lightmapOrSH[2]), asfloat(instance.lightmapOrSH[3]));
                weights = GetLightProbeInterpolationWeight(center, tetIndex, false);
            }
        }
#else
        if (unity_SHAr.x == PERPIXEL_COEFF_TYPE)
        {
            int instanceID = unity_SHAr.y;
            // Non-VG's IntermediaRenderer has no InstanceHeader.
            tetIndex = 0;
            if (instanceID != -1)
                tetIndex = TET_INDEXS(_InstanceSubsetBuffer[instanceID].lightmapOrSH[0]);
            weights = GetLightProbeInterpolationWeight(positionWS, tetIndex, true);
        }
#endif

        shadowMask = CalculateLightOcclusionMask(tetIndex, weights);

#ifdef UNITY_GPU_DRIVEN_PIPELINE
        if (coeffType == AMBIENT_COEFF_TYPE)
#else
        if (unity_SHAr.x == AMBIENT_COEFF_TYPE)
#endif
            return EvaluateAmbientProbe(normalWS);
        else
            return EvaluateLightProbe(normalWS, tetIndex, weights);
    }
}
#endif

// New SampleSH for BakedGINode
half3 SampleSH(half3 normalWS, float3 positionWS UNITY_GDRP_INSTANCE_PARAMETER)
{
#if SUPPORTS_GPU_DRIVEN_LIGHTPROBE
    if (unity_SHC.w == 0.0f)
    {
        // This variable is not used, so it will be optimized.
        half4 shadowMask;
        return SampleSHAndShadowMask(positionWS, normalWS, shadowMask UNITY_GDRP_INSTANCE_ARGUMENT);
    }
#endif

    return SampleSH(normalWS);
}


// SH Vertex Evaluation. Depending on target SH sampling might be
// done completely per vertex or mixed with L2 term per vertex and L0, L1
// per pixel. See SampleSHPixel
half3 SampleSHVertex(half3 normalWS
#if defined(UNITY_GPU_DRIVEN_PIPELINE)
    , bool mayNeedGPU = false
#endif
    )
{
#if SUPPORTS_GPU_DRIVEN_LIGHTPROBE
    // For VG, there's need to calculate sh in the vert stage.
    // For Non-VG with BlendPerPixel, it is the same.
    if (mayNeedGPU && unity_SHC.w == 0.0f)
        return half3(0.0, 0.0, 0.0);
#endif

#if defined(EVALUATE_SH_VERTEX)
    return SampleSH(normalWS);
#elif defined(EVALUATE_SH_MIXED)
    // no max since this is only L2 contribution
    return SHEvalLinearL2(normalWS, unity_SHBr, unity_SHBg, unity_SHBb, unity_SHC);
#endif

    // Fully per-pixel. Nothing to compute.
    return half3(0.0, 0.0, 0.0);
}

// SH Pixel Evaluation. Depending on target SH sampling might be done
// mixed or fully in pixel. See SampleSHVertex
half3 SampleSHPixel(half3 L2Term,
    half3 normalWS
#if defined(UNITY_GPU_DRIVEN_PIPELINE)
    , float3 positionWS
    , inout half4 shadowMask
    UNITY_GDRP_INSTANCE_PARAMETER
    , bool mayNeedGPU = false
#endif
    )
{
    // Attention: If there's any return in the if-condition part, the rest return must be put into the else-condition part,
    // or we will get a warning about 'use of potentially uninitialized variable'
#if SUPPORTS_GPU_DRIVEN_LIGHTPROBE
    if (mayNeedGPU && unity_SHC.w == 0.0f)
        return SampleSHAndShadowMask(positionWS, normalWS, shadowMask UNITY_GDRP_INSTANCE_ARGUMENT);
    else
#endif
    {
#if defined(EVALUATE_SH_VERTEX)
        return L2Term;
#elif defined(EVALUATE_SH_MIXED)
        half3 res = L2Term + SHEvalLinearL0L1(normalWS, unity_SHAr, unity_SHAg, unity_SHAb);
#ifdef UNITY_COLORSPACE_GAMMA
        res = LinearToSRGB(res);
#endif
        return max(half3(0, 0, 0), res);
#endif

        // Default: Evaluate SH fully per-pixel
        return SampleSH(normalWS);
    }
}

#if defined(UNITY_DOTS_INSTANCING_ENABLED) && !defined(USE_LIGHTMAP_SINGLE)
#define LIGHTMAP_NAME unity_Lightmaps
#define LIGHTMAP_INDIRECTION_NAME unity_LightmapsInd
#define LIGHTMAP_SAMPLER_NAME samplerunity_Lightmaps
#define LIGHTMAP_SAMPLE_EXTRA_ARGS staticLightmapUV, unity_LightmapIndex.x
#else
#define LIGHTMAP_NAME unity_Lightmap
#define LIGHTMAP_INDIRECTION_NAME unity_LightmapInd
#define LIGHTMAP_SAMPLER_NAME samplerunity_Lightmap
#define LIGHTMAP_SAMPLE_EXTRA_ARGS staticLightmapUV
#endif

// Sample baked and/or realtime lightmap. Non-Direction and Directional if available.
half3 SampleLightmap(float2 staticLightmapUV, float2 dynamicLightmapUV, half3 normalWS
        UNITY_GDRP_DDXDDY_PARAMETER)
{
#ifdef UNITY_LIGHTMAP_FULL_HDR
    bool encodedLightmap = false;
#else
    bool encodedLightmap = true;
#endif

    half4 decodeInstructions = half4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0h, 0.0h);

    // The shader library sample lightmap functions transform the lightmap uv coords to apply bias and scale.
    // However, universal pipeline already transformed those coords in vertex. We pass half4(1, 1, 0, 0) and
    // the compiler will optimize the transform away.
    half4 transformCoords = half4(1, 1, 0, 0);

    float3 diffuseLighting = 0;

#if defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED)
    diffuseLighting = SampleDirectionalLightmap(TEXTURE2D_LIGHTMAP_ARGS(LIGHTMAP_NAME, LIGHTMAP_SAMPLER_NAME),
        TEXTURE2D_LIGHTMAP_ARGS(LIGHTMAP_INDIRECTION_NAME, LIGHTMAP_SAMPLER_NAME),
        LIGHTMAP_SAMPLE_EXTRA_ARGS, transformCoords, normalWS, encodedLightmap, decodeInstructions
        UNITY_GDRP_DDXDDY_ARGUMENT);
#elif defined(LIGHTMAP_ON)
    diffuseLighting = SampleSingleLightmap(TEXTURE2D_LIGHTMAP_ARGS(LIGHTMAP_NAME, LIGHTMAP_SAMPLER_NAME),
                        LIGHTMAP_SAMPLE_EXTRA_ARGS, transformCoords, encodedLightmap, decodeInstructions
                        UNITY_GDRP_DDXDDY_ARGUMENT);
#endif

#if defined(DYNAMICLIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED)
    diffuseLighting += SampleDirectionalLightmap(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap),
        TEXTURE2D_ARGS(unity_DynamicDirectionality, samplerunity_DynamicLightmap),
        dynamicLightmapUV, transformCoords, normalWS, false, decodeInstructions
        UNITY_GDRP_DDXDDY_ARGUMENT);
#elif defined(DYNAMICLIGHTMAP_ON)
    diffuseLighting += SampleSingleLightmap(TEXTURE2D_ARGS(unity_DynamicLightmap, samplerunity_DynamicLightmap),
        dynamicLightmapUV, transformCoords, false, decodeInstructions
        UNITY_GDRP_DDXDDY_ARGUMENT);
#endif

    return diffuseLighting;
}

// Legacy version of SampleLightmap where Realtime GI is not supported.
half3 SampleLightmap(float2 staticLightmapUV, half3 normalWS
        UNITY_GDRP_DDXDDY_PARAMETER)
{
    float2 dummyDynamicLightmapUV = float2(0,0);
    half3 result = SampleLightmap(staticLightmapUV, dummyDynamicLightmapUV, normalWS
        UNITY_GDRP_DDXDDY_ARGUMENT);
    return result;
}

// We either sample GI from baked lightmap or from probes.
// If lightmap: sampleData.xy = lightmapUV
// If probe: sampleData.xyz = L2 SH terms
#if defined(LIGHTMAP_ON) && defined(DYNAMICLIGHTMAP_ON)
#define SAMPLE_GI(staticLmName, dynamicLmName, shName, normalWSName) SampleLightmap(staticLmName, dynamicLmName, normalWSName)
#elif defined(DYNAMICLIGHTMAP_ON)
#define SAMPLE_GI(staticLmName, dynamicLmName, shName, normalWSName) SampleLightmap(0, dynamicLmName, normalWSName)
#elif defined(LIGHTMAP_ON)
#define SAMPLE_GI(staticLmName, shName, normalWSName) SampleLightmap(staticLmName, 0, normalWSName);
#else
#define SAMPLE_GI(staticLmName, shName, normalWSName) SampleSHPixel(shName, normalWSName)
#endif

#ifdef UNITY_GPU_DRIVEN_PIPELINE
#undef SAMPLE_GI
#if defined(LIGHTMAP_ON)
#define SAMPLE_GI(staticLmName, shName, normalWSName, ddx, ddy, positionWS, shadowMask, instance) \
    SampleLightmap(staticLmName, 0, normalWSName, ddx, ddy); \
    shadowMask = SAMPLE_SHADOWMASK(staticLmName, ddx, ddy);
#else
#define SAMPLE_GI(staticLmName, shName, normalWSName, ddx, ddy, positionWS, shadowMask, instance) SampleSHPixel(shName, normalWSName, positionWS, shadowMask, instance, true)
#endif
#endif

half3 BoxProjectedCubemapDirection(half3 reflectionWS, float3 positionWS, float4 cubemapPositionWS, float4 boxMin, float4 boxMax)
{
    // Is this probe using box projection?
    if (cubemapPositionWS.w > 0.0f)
    {
        float3 boxMinMax = (reflectionWS > 0.0f) ? boxMax.xyz : boxMin.xyz;
        half3 rbMinMax = half3(boxMinMax - positionWS) / reflectionWS;

        half fa = half(min(min(rbMinMax.x, rbMinMax.y), rbMinMax.z));

        half3 worldPos = half3(positionWS - cubemapPositionWS.xyz);

        half3 result = worldPos + reflectionWS * fa;
        return result;
    }
    else
    {
        return reflectionWS;
    }
}

float CalculateProbeWeight(float3 positionWS, float4 probeBoxMin, float4 probeBoxMax)
{
    float blendDistance = probeBoxMax.w;
    float3 weightDir = min(positionWS - probeBoxMin.xyz, probeBoxMax.xyz - positionWS) / blendDistance;
    return saturate(min(weightDir.x, min(weightDir.y, weightDir.z)));
}

half CalculateProbeVolumeSqrMagnitude(float4 probeBoxMin, float4 probeBoxMax)
{
    half3 maxToMin = half3(probeBoxMax.xyz - probeBoxMin.xyz);
    return dot(maxToMin, maxToMin);
}

#if defined(UNITY_GPU_DRIVEN_PIPELINE)
half2 GetReflectionAtlasCoords(half4 scaleOffset, half3 dir, half mip)
{
    half2 uv = saturate(PackNormalOctQuadEncode(dir) * 0.5 + 0.5);
    half2 padding = _ReflectionPaddingData.xy;
    padding *= pow(2.0, max(mip - _ReflectionPaddingData.z, 0.0));
    half2 size = scaleOffset.xy - padding;
    half2 offset = scaleOffset.zw + 0.5 * padding;
    return uv * size + offset;
}

half3 SampleReflectionProbeAtlas(half3 reflectVector, half mip, uint probeIndex)
{
    half3 irradiance = 0;
    if (probeIndex != 0xFF)
    {
        half2 atlasCoords = GetReflectionAtlasCoords(_ReflectionProbeInfoBuffer[probeIndex].scaleOffset, reflectVector, mip);
        irradiance = half3(SAMPLE_TEXTURE2D_LOD(_ReflectionAtlas, sampler_ReflectionAtlas, atlasCoords, mip).xyz);
    }
    return irradiance;
}

#endif

half3 CalculateIrradianceFromReflectionProbes(half3 reflectVector, float3 positionWS, half perceptualRoughness, float2 normalizedScreenSpaceUV UNITY_GDRP_PROBE_INDEX_PARAMETER)
{
    half3 irradiance = half3(0.0h, 0.0h, 0.0h);
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
#if USE_CLUSTERED_LIGHTING
    float totalWeight = 0.0f;
    uint probeIndex;
    ClusterIterator it = ClusterInit(normalizedScreenSpaceUV, positionWS, 1);
    [loop] while (ClusterNext(it, probeIndex) && totalWeight < 0.99f)
    {
        probeIndex -= URP_FP_PROBES_BEGIN;

        float weight = CalculateProbeWeight(positionWS, urp_ReflProbes_BoxMin[probeIndex], urp_ReflProbes_BoxMax[probeIndex]);
        weight = min(weight, 1.0f - totalWeight);

        half3 sampleVector = reflectVector;
#ifdef _REFLECTION_PROBE_BOX_PROJECTION
        sampleVector = BoxProjectedCubemapDirection(reflectVector, positionWS, urp_ReflProbes_ProbePosition[probeIndex], urp_ReflProbes_BoxMin[probeIndex], urp_ReflProbes_BoxMax[probeIndex]);
#endif // _REFLECTION_PROBE_BOX_PROJECTION

        uint maxMip = (uint)abs(urp_ReflProbes_ProbePosition[probeIndex].w) - 1;
        half probeMip = min(mip, maxMip);
        float2 uv = saturate(PackNormalOctQuadEncode(sampleVector) * 0.5 + 0.5);

        float mip0 = floor(probeMip);
        float mip1 = mip0 + 1;
        float mipBlend = probeMip - mip0;
        float4 scaleOffset0 = urp_ReflProbes_MipScaleOffset[probeIndex * 7 + (uint)mip0];
        float4 scaleOffset1 = urp_ReflProbes_MipScaleOffset[probeIndex * 7 + (uint)mip1];

        half3 irradiance0 = half4(SAMPLE_TEXTURE2D_LOD(urp_ReflProbes_Atlas, samplerurp_ReflProbes_Atlas, uv * scaleOffset0.xy + scaleOffset0.zw, 0.0)).rgb;
        half3 irradiance1 = half4(SAMPLE_TEXTURE2D_LOD(urp_ReflProbes_Atlas, samplerurp_ReflProbes_Atlas, uv * scaleOffset1.xy + scaleOffset1.zw, 0.0)).rgb;
        irradiance += weight * lerp(irradiance0, irradiance1, mipBlend);
        totalWeight += weight;
    }
#else
    half probe0Volume = CalculateProbeVolumeSqrMagnitude(unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
    half probe1Volume = CalculateProbeVolumeSqrMagnitude(unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);

    half volumeDiff = probe0Volume - probe1Volume;
    float importanceSign = unity_SpecCube1_BoxMin.w;

    // A probe is dominant if its importance is higher
    // Or have equal importance but smaller volume
    bool probe0Dominant = importanceSign > 0.0f || (importanceSign == 0.0f && volumeDiff < -0.0001h);
    bool probe1Dominant = importanceSign < 0.0f || (importanceSign == 0.0f && volumeDiff > 0.0001h);

    float desiredWeightProbe0 = CalculateProbeWeight(positionWS, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
    float desiredWeightProbe1 = CalculateProbeWeight(positionWS, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);

    // Subject the probes weight if the other probe is dominant
    float weightProbe0 = probe1Dominant ? min(desiredWeightProbe0, 1.0f - desiredWeightProbe1) : desiredWeightProbe0;
    float weightProbe1 = probe0Dominant ? min(desiredWeightProbe1, 1.0f - desiredWeightProbe0) : desiredWeightProbe1;

    float totalWeight = weightProbe0 + weightProbe1;

    // If either probe 0 or probe 1 is dominant the sum of weights is guaranteed to be 1.
    // If neither is dominant this is not guaranteed - only normalize weights if totalweight exceeds 1.
    weightProbe0 /= max(totalWeight, 1.0f);
    weightProbe1 /= max(totalWeight, 1.0f);

    // Sample the first reflection probe
    if (weightProbe0 > 0.01f)
    {
        half3 reflectVector0 = reflectVector;
#ifdef _REFLECTION_PROBE_BOX_PROJECTION
        reflectVector0 = BoxProjectedCubemapDirection(reflectVector, positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
#endif // _REFLECTION_PROBE_BOX_PROJECTION

#if defined(UNITY_GPU_DRIVEN_PIPELINE)
        uint textureValid = BitFieldExtractU32(_ReflectionProbeInfoBuffer[probeIndex0].boxProjection_TextureValid_Importance, VG_REFLECTION_PROBE_INFO_TEXTURE_VALID_BITS, VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS);
        if (textureValid > 0)
        {
            irradiance += weightProbe0 * SampleReflectionProbeAtlas(reflectVector0, mip, probeIndex0);
        }
#else
        half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector0, mip));
        irradiance += weightProbe0 * DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
#endif
    }

    // Sample the second reflection probe
    if (weightProbe1 > 0.01f)
    {
        half3 reflectVector1 = reflectVector;
#ifdef _REFLECTION_PROBE_BOX_PROJECTION
        reflectVector1 = BoxProjectedCubemapDirection(reflectVector, positionWS, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax);
#endif // _REFLECTION_PROBE_BOX_PROJECTION

#if defined(UNITY_GPU_DRIVEN_PIPELINE)
        uint textureValid = BitFieldExtractU32(_ReflectionProbeInfoBuffer[probeIndex1].boxProjection_TextureValid_Importance, VG_REFLECTION_PROBE_INFO_TEXTURE_VALID_BITS, VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS);
        if (textureValid > 0)
        {
            irradiance += weightProbe1 * SampleReflectionProbeAtlas(reflectVector1, mip, probeIndex1);
        }
#else
        half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube1, samplerunity_SpecCube1, reflectVector1, mip));
        irradiance += weightProbe1 * DecodeHDREnvironment(encodedIrradiance, unity_SpecCube1_HDR);
#endif
    }
#endif

    // Use any remaining weight to blend to environment reflection cube map
    if (totalWeight < 0.99f)
    {
        half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, sampler_GlossyEnvironmentCubeMap, reflectVector, mip));

        irradiance += (1.0f - totalWeight) * DecodeHDREnvironment(encodedIrradiance, _GlossyEnvironmentCubeMap_HDR);
    }

    return irradiance;
}

// #if !USE_CLUSTERED_LIGHTING
// half3 CalculateIrradianceFromReflectionProbes(half3 reflectVector, float3 positionWS, half perceptualRoughness)
// {
//     return CalculateIrradianceFromReflectionProbes(reflectVector, positionWS, perceptualRoughness, float2(0.0f, 0.0f));
// }
// #endif

half3 GlossyEnvironmentReflection(half3 reflectVector, float3 positionWS, half perceptualRoughness, half occlusion, float2 normalizedScreenSpaceUV UNITY_GDRP_INSTANCE_PARAMETER)
{
#if !defined(_ENVIRONMENTREFLECTIONS_OFF)
    half3 irradiance = 0;

#if defined(UNITY_GPU_DRIVEN_PIPELINE)
    uint probeIndex0;
    uint probeIndex1;
    UnpackReflectionProbeParam(instance.reflectionProbeParameter, probeIndex0, probeIndex1);    
#endif

#if defined(_REFLECTION_PROBE_BLENDING) || USE_CLUSTERED_LIGHTING
    irradiance = CalculateIrradianceFromReflectionProbes(reflectVector, positionWS, perceptualRoughness, normalizedScreenSpaceUV UNITY_GDRP_PROBE_INDEX_ARGUMENT);
#else
#ifdef _REFLECTION_PROBE_BOX_PROJECTION
    reflectVector = BoxProjectedCubemapDirection(reflectVector, positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax);
#endif // _REFLECTION_PROBE_BOX_PROJECTION
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    half4 encodedIrradiance;
#if defined(UNITY_GPU_DRIVEN_PIPELINE)
    if (probeIndex0 != 0xFF)
    {
        uint textureValid = BitFieldExtractU32(_ReflectionProbeInfoBuffer[probeIndex0].boxProjection_TextureValid_Importance, VG_REFLECTION_PROBE_INFO_TEXTURE_VALID_BITS, VG_REFLECTION_PROBE_INFO_IMPORTANCE_BITS);
        if (textureValid > 0)
        {
            irradiance = SampleReflectionProbeAtlas(reflectVector, mip, probeIndex0);
        }
    }
    else
    {
        half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, sampler_GlossyEnvironmentCubeMap, reflectVector, mip));
        irradiance = DecodeHDREnvironment(encodedIrradiance, _GlossyEnvironmentCubeMap_HDR);
    }
#else
    encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));
    irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
#endif // UNITY_GPU_DRIVEN_PIPELINE

#endif // _REFLECTION_PROBE_BLENDING
    return irradiance * occlusion;
#else
    return _GlossyEnvironmentColor.rgb * occlusion;
#endif // _ENVIRONMENTREFLECTIONS_OFF
}

#if !USE_CLUSTERED_LIGHTING
half3 GlossyEnvironmentReflection(half3 reflectVector, float3 positionWS, half perceptualRoughness, half occlusion)
{
    return GlossyEnvironmentReflection(reflectVector, positionWS, perceptualRoughness, occlusion, float2(0.0f, 0.0f) UNITY_GDRP_INSTANCE_ZERO_ARGUMENT);
}
#endif

half3 GlossyEnvironmentReflection(half3 reflectVector, half perceptualRoughness, half occlusion UNITY_GDRP_PROBE_INDEX_PARAMETER)
{
#if !defined(_ENVIRONMENTREFLECTIONS_OFF)
    half3 irradiance;
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip));

    irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);

    return irradiance * occlusion;
#else

    return _GlossyEnvironmentColor.rgb * occlusion;
#endif // _ENVIRONMENTREFLECTIONS_OFF
}

half3 SubtractDirectMainLightFromLightmap(Light mainLight, half3 normalWS, half3 bakedGI)
{
    // Let's try to make realtime shadows work on a surface, which already contains
    // baked lighting and shadowing from the main sun light.
    // Summary:
    // 1) Calculate possible value in the shadow by subtracting estimated light contribution from the places occluded by realtime shadow:
    //      a) preserves other baked lights and light bounces
    //      b) eliminates shadows on the geometry facing away from the light
    // 2) Clamp against user defined ShadowColor.
    // 3) Pick original lightmap value, if it is the darkest one.


    // 1) Gives good estimate of illumination as if light would've been shadowed during the bake.
    // We only subtract the main direction light. This is accounted in the contribution term below.
    half shadowStrength = GetMainLightShadowStrength();
    half contributionTerm = saturate(dot(mainLight.direction, normalWS));
    half3 lambert = mainLight.color * contributionTerm;
    half3 estimatedLightContributionMaskedByInverseOfShadow = lambert * (1.0 - mainLight.shadowAttenuation);
    half3 subtractedLightmap = bakedGI - estimatedLightContributionMaskedByInverseOfShadow;

    // 2) Allows user to define overall ambient of the scene and control situation when realtime shadow becomes too dark.
    half3 realtimeShadow = max(subtractedLightmap, _SubtractiveShadowColor.xyz);
    realtimeShadow = lerp(bakedGI, realtimeShadow, shadowStrength);

    // 3) Pick darkest color
    return min(bakedGI, realtimeShadow);
}

half3 GlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, float clearCoatMask,
    half3 bakedGI, half occlusion, float3 positionWS,
    half3 normalWS, half3 viewDirectionWS, float2 normalizedScreenSpaceUV
    UNITY_GDRP_INSTANCE_PARAMETER)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h, normalizedScreenSpaceUV UNITY_GDRP_INSTANCE_ARGUMENT);

    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

    if (IsOnlyAOLightingFeatureEnabled())
    {
        color = half3(1,1,1); // "Base white" for AO debug lighting mode
    }

#if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
    half3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfDataClearCoat.perceptualRoughness, 1.0h, normalizedScreenSpaceUV UNITY_GDRP_INSTANCE_ARGUMENT);
    // TODO: "grazing term" causes problems on full roughness
    half3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, clearCoatMask, coatIndirectSpecular, fresnelTerm);

    // Blend with base layer using khronos glTF recommended way using NoV
    // Smooth surface & "ambiguous" lighting
    // NOTE: fresnelTerm (above) is pow4 instead of pow5, but should be ok as blend weight.
    half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * fresnelTerm;
    return (color * (1.0 - coatFresnel * clearCoatMask) + coatColor) * occlusion;
#else
    return color * occlusion;
#endif
}

#if !USE_CLUSTERED_LIGHTING
half3 GlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, float clearCoatMask,
    half3 bakedGI, half occlusion, float3 positionWS,
    half3 normalWS, half3 viewDirectionWS)
{
    return GlobalIllumination(brdfData, brdfDataClearCoat, clearCoatMask, bakedGI, occlusion, positionWS, normalWS, viewDirectionWS, float2(0.0f, 0.0f) UNITY_GDRP_INSTANCE_ZERO_ARGUMENT);
}
#endif

// Backwards compatiblity
half3 GlobalIllumination(BRDFData brdfData, half3 bakedGI, half occlusion, float3 positionWS, half3 normalWS, half3 viewDirectionWS UNITY_GDRP_INSTANCE_PARAMETER)
{
    const BRDFData noClearCoat = (BRDFData)0;
    return GlobalIllumination(brdfData, noClearCoat, 0.0, bakedGI, occlusion, positionWS, normalWS, viewDirectionWS, 0 UNITY_GDRP_INSTANCE_ARGUMENT);
}

half3 GlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, float clearCoatMask,
    half3 bakedGI, half occlusion,
    half3 normalWS, half3 viewDirectionWS)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NoV = saturate(dot(normalWS, viewDirectionWS));
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, half(1.0) UNITY_GDRP_PROBE_INDEX_ZERO_ARGUMENT);

    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

#if defined(_CLEARCOAT) || defined(_CLEARCOATMAP)
    half3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, brdfDataClearCoat.perceptualRoughness, half(1.0) UNITY_GDRP_PROBE_INDEX_ZERO_ARGUMENT);
    // TODO: "grazing term" causes problems on full roughness
    half3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, clearCoatMask, coatIndirectSpecular, fresnelTerm);

    // Blend with base layer using khronos glTF recommended way using NoV
    // Smooth surface & "ambiguous" lighting
    // NOTE: fresnelTerm (above) is pow4 instead of pow5, but should be ok as blend weight.
    half coatFresnel = kDielectricSpec.x + kDielectricSpec.a * fresnelTerm;
    return (color * (1.0 - coatFresnel * clearCoatMask) + coatColor) * occlusion;
#else
    return color * occlusion;
#endif
}


half3 GlobalIllumination(BRDFData brdfData, half3 bakedGI, half occlusion, half3 normalWS, half3 viewDirectionWS)
{
    const BRDFData noClearCoat = (BRDFData)0;
    return GlobalIllumination(brdfData, noClearCoat, 0.0, bakedGI, occlusion, normalWS, viewDirectionWS);
}

// For Complex Lit
half3 GlobalIllumination(BRDFData brdfData, BRDFData brdfDataClearCoat, InputData inputData, SurfaceData surfaceData,  half occlusion
#if (defined(_CLEARCOAT) || defined(_CLEARCOATMAP)) && defined(_SCALABLE_LIT)
    , half3 clearCoatNormal
#endif
#if defined(_SPECULAR_MODEL_ANISO)
    , half3 tangentWS, half3 bitangentWS, half3 anisoNormalWS
#endif
#if defined(_THIN_FILM)
    , half3 iridescence
#endif
)
{
    half3 viewDirWS = inputData.viewDirectionWS;
#if defined(_SPECULAR_MODEL_ANISO)
    half3 normalWS = anisoNormalWS;
#else
    half3 normalWS = inputData.normalWS;
#endif
    half3 positionWS = inputData.positionWS;
    half2 normalizedScreenSpaceUV = inputData.normalizedScreenSpaceUV;
    half3 bakedGI = inputData.bakedGI;
    half NoV = saturate(dot(normalWS, viewDirWS));
    half3 reflectVector = reflect(-viewDirWS, normalWS);
    half fresnelTerm = Pow4(1.0 - NoV);

    half3 indirectDiffuse = bakedGI;
    #if _CUSTOM_INDIRECT_DIFFUSE
        if (surfaceData.indirectDiffuseMask < 1)
            indirectDiffuse = lerp(bakedGI, surfaceData.indirectDiffuse, surfaceData.indirectDiffuseMask);
        else
            indirectDiffuse = surfaceData.indirectDiffuse;
    #else
        indirectDiffuse = bakedGI;
    #endif
    half3 indirectSpecular = 0;
    #if _CUSTOM_INDIRECT_SPECULAR
        if (surfaceData.indirectSpecularMask < 1)
            indirectSpecular = lerp(GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h, normalizedScreenSpaceUV), surfaceData.indirectSpecular, surfaceData.indirectSpecularMask);
        else
            indirectSpecular = surfaceData.indirectSpecular;
    #else
        // @TODO: There's a warning about 'implicit truncation of vector type' on Metal, but acctually, we cannot
        // find any truncation here. So it may be caused by ShaderCompiler, and just ignore it now.
        indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h, normalizedScreenSpaceUV);
    #endif

    #if _DIFFRACTION_GRATINGS
    half3 diffractionGrating = DiffractionGrating(normalWS, viewDirWS, surfaceData.slitsDirection, normalWS, surfaceData.slitsDistance);
    #endif

    #if (defined(_CLEARCOAT) || defined(_CLEARCOATMAP)) && defined(_SCALABLE_LIT)
        half clearCoatFresnelTerm = Pow4(1.0 - saturate(dot(clearCoatNormal, viewDirWS)));
        half coatFresnel = (kDielectricSpec.x + kDielectricSpec.a * clearCoatFresnelTerm);
    #endif

    half3 color = EnvironmentBRDF_Scalable(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm
    #if (defined(_CLEARCOAT) || defined(_CLEARCOATMAP)) && defined(_SCALABLE_LIT)
        , (1 - coatFresnel * surfaceData.clearCoatMask)
    #endif
    #if defined(_THIN_FILM)
        , iridescence, surfaceData.thinFilmMask
    #endif
    #if defined(_DIFFRACTION_GRATINGS)
        , diffractionGrating, surfaceData.slitsMask
    #endif
    #if defined(_USE_PREINTEGRATED_FDG)
        , surfaceData.customSpecularFDG, surfaceData.customEnergyCompensation
    #endif
        );


if (IsOnlyAOLightingFeatureEnabled())
    {
        color = half3(1,1,1); // "Base white" for AO debug lighting mode
    }

#if (defined(_CLEARCOAT) || defined(_CLEARCOATMAP)) && defined(_SCALABLE_LIT)
    reflectVector = reflect(-viewDirWS, clearCoatNormal);
    half3 coatIndirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfDataClearCoat.perceptualRoughness, 1.0h, normalizedScreenSpaceUV);

    // TODO: "grazing term" causes problems on full roughness
    half3 coatColor = EnvironmentBRDFClearCoat(brdfDataClearCoat, surfaceData.clearCoatMask, coatIndirectSpecular, clearCoatFresnelTerm);

    // Blend with base layer using khronos glTF recommended way using NoV
    // Smooth surface & "ambiguous" lighting
    // NOTE: fresnelTerm (above) is pow4 instead of pow5, but should be ok as blend weight.
    return (color + coatColor) * occlusion;
#else
    return color * occlusion;
#endif
}

void MixRealtimeAndBakedGI(inout Light light, half3 normalWS, inout half3 bakedGI)
{
#if defined(LIGHTMAP_ON) && defined(_MIXED_LIGHTING_SUBTRACTIVE)
    bakedGI = SubtractDirectMainLightFromLightmap(light, normalWS, bakedGI);
#endif
}

// Backwards compatibility
void MixRealtimeAndBakedGI(inout Light light, half3 normalWS, inout half3 bakedGI, half4 shadowMask)
{
    MixRealtimeAndBakedGI(light, normalWS, bakedGI);
}

void MixRealtimeAndBakedGI(inout Light light, half3 normalWS, inout half3 bakedGI, AmbientOcclusionFactor aoFactor)
{
    if (IsLightingFeatureEnabled(DEBUGLIGHTINGFEATUREFLAGS_AMBIENT_OCCLUSION))
    {
        bakedGI *= aoFactor.indirectAmbientOcclusion;
    }

    MixRealtimeAndBakedGI(light, normalWS, bakedGI);
}

#endif
