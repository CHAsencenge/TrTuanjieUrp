#ifndef UNIVERSAL_DEFERRED_PLUS_SHADING_INCLUDED
#define UNIVERSAL_DEFERRED_PLUS_SHADING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    uint vertexID : SV_VertexID;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float3 screenUV : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

Varyings Vertex(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    float3 positionOS = input.positionOS.xyz;
    // Full screen render using a large triangle.
    output.positionCS = float4(positionOS.xy, UNITY_RAW_FAR_CLIP_VALUE, 1.0); // Force triangle to be on zfar
    output.screenUV = output.positionCS.xyw;
    #if UNITY_UV_STARTS_AT_TOP
    output.screenUV.xy = output.screenUV.xy * float2(0.5, -0.5) + 0.5 * output.screenUV.z;
    #else
    output.screenUV.xy = output.screenUV.xy * 0.5 + 0.5 * output.screenUV.z;
    #endif

    return output;
}

TEXTURE2D_X(_CameraDepthTexture);
TEXTURE2D_X_HALF(_GBuffer0);
TEXTURE2D_X_HALF(_GBuffer1);
TEXTURE2D_X_HALF(_GBuffer2);

#if _RENDER_PASS_ENABLED

#define GBUFFER0 0
#define GBUFFER1 1
#define GBUFFER2 2
#define GBUFFER3 3

FRAMEBUFFER_INPUT_HALF(GBUFFER0);
FRAMEBUFFER_INPUT_HALF(GBUFFER1);
FRAMEBUFFER_INPUT_HALF(GBUFFER2);
FRAMEBUFFER_INPUT_FLOAT(GBUFFER3);
#if OUTPUT_SHADOWMASK
#define GBUFFER4 4
FRAMEBUFFER_INPUT_HALF(GBUFFER4);
#endif
#else
#ifdef GBUFFER_OPTIONAL_SLOT_1
TEXTURE2D_X_HALF(_GBuffer4);
#endif
#endif

#if defined(GBUFFER_OPTIONAL_SLOT_2) && _RENDER_PASS_ENABLED
TEXTURE2D_X_HALF(_GBuffer5);
#elif defined(GBUFFER_OPTIONAL_SLOT_2)
TEXTURE2D_X(_GBuffer5);
#endif
#ifdef GBUFFER_OPTIONAL_SLOT_3
TEXTURE2D_X(_GBuffer6);
#endif

float4x4 _ScreenToWorld[2];
SamplerState my_point_clamp_sampler;

half3 DeferredShadingCommon(Light unityLight, InputData inputData, FragmentOutput gbufferData, uint materialFlags)
{
    half3 color = half3(0.0f, 0.0f, 0.0f);
    
    #if defined(_SIMPLELIT)
    SurfaceData surfaceData = SurfaceDataFromGbuffer(gbufferData.GBuffer0, gbufferData.GBuffer1, gbufferData.GBuffer2, kLightingSimpleLit);
    half3 attenuatedLightColor = unityLight.color * (unityLight.distanceAttenuation * unityLight.shadowAttenuation);
    half3 diffuseColor = LightingLambert(attenuatedLightColor, unityLight.direction, inputData.normalWS);
    half smoothness = exp2(10 * surfaceData.smoothness + 1);
    half3 specularColor = LightingSpecular(attenuatedLightColor, unityLight.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), smoothness);

    // TODO: if !defined(_SPECGLOSSMAP) && !defined(_SPECULAR_COLOR), force specularColor to 0 in gbuffer code
    color = diffuseColor * surfaceData.albedo + specularColor;
    #else // _LIT
    #if SHADER_API_MOBILE || SHADER_API_SWITCH
    // Specular highlights are still silenced by setting specular to 0.0 during gbuffer pass and GPU timing is still reduced.
    bool materialSpecularHighlightsOff = false;
    #else
    bool materialSpecularHighlightsOff = (materialFlags & kMaterialFlagSpecularHighlightsOff);
    #endif

    BRDFData brdfData = BRDFDataFromGbuffer(gbufferData.GBuffer0, gbufferData.GBuffer1, gbufferData.GBuffer2);
    color = half3(LightingPhysicallyBased(brdfData, unityLight, inputData.normalWS, inputData.viewDirectionWS, materialSpecularHighlightsOff));
    #endif
    
    return color;
}

Light GetDeferredMainLight(float3 posWS, half4 shadowMask, uint materialFlags)
{
    Light unityLight = GetMainLight();

    bool materialReceiveShadowsOff = (materialFlags & kMaterialFlagReceiveShadowsOff) != 0;

    if (!materialReceiveShadowsOff)
    {
        #if defined(_MAIN_LIGHT_SHADOWS_SCREEN) && !defined(_SURFACE_TYPE_TRANSPARENT)
        float4 shadowCoord = float4(screen_uv, 0.0, 1.0);
        #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        float4 shadowCoord = TransformWorldToShadowCoord(posWS.xyz);
        #else
        float4 shadowCoord = float4(0, 0, 0, 0);
        #endif
        unityLight.shadowAttenuation = MainLightShadow(shadowCoord, posWS.xyz, shadowMask, _MainLightOcclusionProbes);
    }

    #if defined(_LIGHT_COOKIES)
    real3 cookieColor = SampleMainLightCookie(posWS);
    unityLight.color *= half3(cookieColor);
    #endif
    return unityLight;
}

half3 DeferredMainLightShading(InputData inputData, FragmentOutput gbufferData, float3 posWS, half4 shadowMask, AmbientOcclusionFactor aoFactor, uint meshRenderingLayers, uint materialFlags)
{
    Light unityLight = GetDeferredMainLight(posWS, shadowMask, materialFlags);
    
    // color.w == 0 for MainLight means Subtractive Light (distanceAttenuation)
    // Why MainLightColor.w and AdditionalLightColor.w acts differently?
    #if defined(_DEFERRED_MIXED_LIGHTING)
    // If both lights and geometry are static, then no realtime lighting to perform for this combination.
    [branch] if (_MainLightColor.w == 0 && (materialFlags & kMaterialFlagSubtractiveMixedLighting) != 0)
        return half3(0.0, 0.0, 0.0);
    #endif

    #ifdef _LIGHT_LAYERS
    [branch] if (!IsMatchingLightLayer(unityLight.layerMask, meshRenderingLayers))
        return half3(0.0, 0.0, 0.0);
    #endif

    #if defined(_SCREEN_SPACE_OCCLUSION)
    unityLight.color *= aoFactor.directAmbientOcclusion;
    #endif

    return DeferredShadingCommon(unityLight, inputData, gbufferData, materialFlags);
}

half3 DeferredAdditionalLightShading(uint lightIndex, InputData inputData, FragmentOutput gbufferData, float3 posWS, half4 shadowMask, AmbientOcclusionFactor aoFactor, uint meshRenderingLayers, uint materialFlags)
{
    Light unityLight = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
    bool materialReceiveShadowsOff = (materialFlags & kMaterialFlagReceiveShadowsOff) != 0;
    if (materialReceiveShadowsOff)
    {
        unityLight.shadowAttenuation = 1.0;
    }

    // color.w == 1 for AdditionalLight means Subtractive Light
    // Why MainLightColor.w and AdditionalLightColor.w acts differently?
    #if defined(_DEFERRED_MIXED_LIGHTING)
    // If both lights and geometry are static, then no realtime lighting to perform for this combination.
    [branch] if (_AdditionalLightsColor[lightIndex].w > 0 && (materialFlags & kMaterialFlagSubtractiveMixedLighting) != 0)
        return half3(0.0, 0.0, 0.0);
    #endif

    #ifdef _LIGHT_LAYERS
    [branch] if (!IsMatchingLightLayer(unityLight.layerMask, meshRenderingLayers))
        return half3(0.0, 0.0, 0.0);
    #endif

    return DeferredShadingCommon(unityLight, inputData, gbufferData, materialFlags);
}

half4 Fragment(Varyings input) : SV_TARGET
{
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    float2 screen_uv = (input.screenUV.xy / input.screenUV.z);

    #if defined(SUPPORTS_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
    float2 undistorted_screen_uv = screen_uv;
    UNITY_BRANCH if (_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
    {
        screen_uv = input.positionCS.xy * _ScreenSize.zw;
    }
    #endif

    half4 shadowMask = 1.0;

    #if _RENDER_PASS_ENABLED
    float d        = LOAD_FRAMEBUFFER_INPUT(GBUFFER3, input.positionCS.xy).x;
    half4 gbuffer0 = LOAD_FRAMEBUFFER_INPUT(GBUFFER0, input.positionCS.xy);
    half4 gbuffer1 = LOAD_FRAMEBUFFER_INPUT(GBUFFER1, input.positionCS.xy);
    half4 gbuffer2 = LOAD_FRAMEBUFFER_INPUT(GBUFFER2, input.positionCS.xy);
    #if defined(_DEFERRED_MIXED_LIGHTING)
    shadowMask = LOAD_FRAMEBUFFER_INPUT(GBUFFER4, input.positionCS.xy);
    #endif
    #else
    // Using SAMPLE_TEXTURE2D is faster than using LOAD_TEXTURE2D on iOS platforms (5% faster shader).
    // Possible reason: HLSLcc upcasts Load() operation to float, which doesn't happen for Sample()?
    float d        = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, my_point_clamp_sampler, screen_uv, 0).x; // raw depth value has UNITY_REVERSED_Z applied on most platforms.
    half4 gbuffer0 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, my_point_clamp_sampler, screen_uv, 0);
    half4 gbuffer1 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer1, my_point_clamp_sampler, screen_uv, 0);
    half4 gbuffer2 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer2, my_point_clamp_sampler, screen_uv, 0);
    #if defined(_DEFERRED_MIXED_LIGHTING)
    shadowMask = SAMPLE_TEXTURE2D_X_LOD(MERGE_NAME(_, GBUFFER_SHADOWMASK), my_point_clamp_sampler, screen_uv, 0);
    #endif
    #endif

    half surfaceDataOcclusion = gbuffer1.a;
    uint materialFlags = UnpackMaterialFlags(gbuffer0.a);
    
    #if defined(SUPPORTS_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
    UNITY_BRANCH if (_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
    {
        input.positionCS.xy = undistorted_screen_uv * _ScreenSize.xy;
    }
    #endif

    #if defined(USING_STEREO_MATRICES)
    int eyeIndex = unity_StereoEyeIndex;
    #else
    int eyeIndex = 0;
    #endif
    float4 posWS = mul(_ScreenToWorld[eyeIndex], float4(input.positionCS.xy, d, 1.0));
    posWS.xyz *= rcp(posWS.w);

    #ifdef _LIGHT_LAYERS
    float4 renderingLayers = SAMPLE_TEXTURE2D_X_LOD(MERGE_NAME(_, GBUFFER_LIGHT_LAYERS), my_point_clamp_sampler, screen_uv, 0);
    uint meshRenderingLayers = DecodeMeshRenderingLayer(renderingLayers.r);
    #else
    uint meshRenderingLayers = 0;
    #endif

    half3 color = half3(0.0, 0.0, 0.0);
    half alpha = 1.0;

    AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(screen_uv);
    
    #if defined(_SCREEN_SPACE_OCCLUSION)
    // What we want is really to apply the minimum occlusion value between the baked occlusion from surfaceDataOcclusion and real-time occlusion from SSAO.
    // But we already applied the baked occlusion during gbuffer pass, so we have to cancel it out here.
    // We must also avoid divide-by-0 that the reciprocal can generate.
    half occlusion = aoFactor.indirectAmbientOcclusion < surfaceDataOcclusion ? aoFactor.indirectAmbientOcclusion * rcp(surfaceDataOcclusion) : 1.0;
    alpha = occlusion;
    #endif
    
    InputData inputData = InputDataFromGbufferAndWorldPosition(gbuffer2, posWS.xyz);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);   // required by Clustered Light Iterator
    
    FragmentOutput gbufferData;
    gbufferData.GBuffer0 = gbuffer0;
    gbufferData.GBuffer1 = gbuffer1;
    gbufferData.GBuffer2 = gbuffer2;
    gbufferData.GBuffer3 = half4(0.0, 0.0, 0.0, 0.0);   // not used by following code
    
    // Main Light
    color = DeferredMainLightShading(inputData, gbufferData, posWS.xyz, shadowMask, aoFactor, meshRenderingLayers, materialFlags);

    // Additional Directional Lights
    #if USE_CLUSTERED_LIGHTING
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        color += DeferredAdditionalLightShading(lightIndex, inputData, gbufferData, posWS.xyz, shadowMask, aoFactor, meshRenderingLayers, materialFlags);
    }
    #endif

    uint pixelLightCount = GetAdditionalLightsCount();
    LIGHT_LOOP_BEGIN(pixelLightCount)
        color += DeferredAdditionalLightShading(lightIndex, inputData, gbufferData, posWS.xyz, shadowMask, aoFactor, meshRenderingLayers, materialFlags);
    LIGHT_LOOP_END

    return half4(color, alpha);
}

#endif
