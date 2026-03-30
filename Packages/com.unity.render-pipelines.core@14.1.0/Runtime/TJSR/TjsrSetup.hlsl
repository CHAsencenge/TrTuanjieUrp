#ifndef TJSR_SETUP
#define TJSR_SETUP

#include "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrCommon.hlsl"
	
TEXTURE2D_X(_TjsrMotionVectorTex);


void TjsrSetupFragment(Varyings input
#if _TJSR_PACK_DEPTH_MOTION
    , out uint outMotionDepthBuffer : SV_Target0
#else
    , out half4 outMotionDepthBuffer : SV_Target0
#endif
#if _TJSR_YCOCG
    #if TJSR_UINT_INTERMEDIATE
    , out uint outIntermediateColor : SV_Target1
    #else
    , out real4 outIntermediateColor : SV_Target1
    #endif
#endif
    )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
    
    int qualityLevel = DecodeQualityLevel(int(_qualityLevel));

#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
    real bestDepth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv - _SourceSize.xy).x;
    real4 btmRight = GATHER_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv);
    real2 topRight = GATHER_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(-1, 0)).xy;
    real2 btmLeft = GATHER_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(0, 1)).yz;
#if UNITY_REVERSED_Z
    bestDepth = 1.0 - bestDepth;
    btmRight = 1.0 - btmRight;
    topRight = 1.0 - topRight;
    btmLeft = 1.0 - btmLeft;
#endif

    // Find the UV offset of the best depth for MotionVectorMap
    real2 bestOffset = real2(-1.0f, -1.0f);
    if (bestDepth < btmRight.w)
    {
        bestOffset = real2(0.0f, 0.0f);
        bestDepth = btmRight.w;
    }
    if (bestDepth < btmRight.x)
    {
        bestOffset = real2(0.0f, 1.0f);
        bestDepth = btmRight.x;
    }
    if (bestDepth < btmRight.y)
    {
        bestOffset = real2(1.0f, 1.0f);
        bestDepth = btmRight.y;
    }
    if (bestDepth < btmRight.z)
    {
        bestOffset = real2(1.0f, 0.0f);
        bestDepth = btmRight.z;
    }
    if (bestDepth < topRight.x)
    {
        bestOffset = real2(0.0f, -1.0f);
        bestDepth = topRight.x;
    }
    if (bestDepth < topRight.y)
    {
        bestOffset = real2(1.0f, -1.0f);
        bestDepth = topRight.y;
    }
    if (bestDepth < btmLeft.x)
    {
        bestOffset = real2(-1.0f, 1.0f);
        bestDepth = btmLeft.x;
    }
    if (bestDepth < btmLeft.y)
    {
        bestOffset = real2(-1.0f, 0.0f);
        bestDepth = btmLeft.y;
    }
#else
    half bestOffsetX = 0.0f;
    half bestOffsetY = 0.0f;
    real bestDepth = 1.0f;
    // texture gather to find nearest depth
    AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 0.0f, 0.0f);
    AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 1.0f, 0.0f);
    AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 0.0f, -1.0f);
    AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, -1.0f, 0.0f);
    AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 0.0f, 1.0f);
    if (qualityLevel >= 1)
    {
        AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, -1.0f, -1.0f);
        AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 1.0f, -1.0f);
        AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, -1.0f, 1.0f);
        AdjustBestDepthOffset(bestDepth, bestOffsetX, bestOffsetY, uv, 1.0f, 1.0f);
    }
    half2 bestOffset = half2(bestOffsetX, bestOffsetY);
#endif
    
    half2 motion = GetVelocityWithOffset(uv, bestOffset, _TjsrMotionVectorTex);
    
#if UNITY_REVERSED_Z
    bestDepth = 1.0 - Linear01Depth(1.0 - bestDepth, _ZBufferParams);
#else
    bestDepth = 1.0 - Linear01Depth(bestDepth, _ZBufferParams);
#endif

    real alpha_mask = real(0.0f);
#if _TJSR_YCOCG
    // Generate color in ycocg space
    real4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);  // Point == Linear as uv == input pixel center.
    real4 workingCol = SceneToWorkingSpace(col);
    #if defined (HAS_OPAQUE_MASK)
    real4 opaqueCol = SAMPLE_TEXTURE2D_X(_BlitOpaqueTexture, sampler_PointClamp, uv);
    real4 opaqueWorkingCol = SceneToWorkingSpace(opaqueCol);
    real4 delta = abs(workingCol - opaqueWorkingCol);
    alpha_mask = max(delta.x, max(delta.y, delta.z));
    alpha_mask = (0.35f * 1000.0f) * alpha_mask;
    #endif

    #if TJSR_UINT_INTERMEDIATE
    outIntermediateColor = PackR11G11B10ColorToUint(workingCol.rgb);
    #else
    outIntermediateColor = workingCol;
    #endif
#endif//_TJSR_YCOCG

#if _TJSR_PACK_DEPTH_MOTION
    outMotionDepthBuffer = PackMvDepth(motion, bestDepth);
#else
    outMotionDepthBuffer = real4(motion, bestDepth, alpha_mask);
#endif
}

#endif//TJSR_SETUP
