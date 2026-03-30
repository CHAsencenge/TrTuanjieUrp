#ifndef TJSR_DEBUG
#define TJSR_DEBUG

#include "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrCommon.hlsl"

#if _TJSR_UINT_INTERMEDIATE
    TEXTURE2D_X_UINT(_TjsrIntermediateColor);
#else
    TEXTURE2D_X(_TjsrIntermediateColor);
#endif

    TEXTURE2D_X(_TjsrLumaHistory);

#if _TJSR_PACK_DEPTH_MOTION
    TEXTURE2D_X_UINT(_TjsrMotionDepthBuffer);
#else
    TEXTURE2D_X_HALF(_TjsrMotionDepthBuffer);
#endif

#if _TJSR_HAS_ACTIVE_PASS
    TEXTURE2D_X(_TjsrDepthClip);
#endif

void TjsrDebugFragment(Varyings input
    , out half4 outDebugView : SV_Target0
    )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

    int debugViewIndex = DecodeDebugViewIndex(int(_qualityLevel));

    if(debugViewIndex == 1){
#if _TJSR_UINT_INTERMEDIATE
        uint lumaReference32 = FetchUintLuma(uv, int2(0, 0), _TjsrIntermediateColor);
        half lumaReference = UnpackUintToLuma(lumaReference32);
#else
        half lumaReference = GetLuma(SAMPLE_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv).rgb);
#endif
        outDebugView = half4(lumaReference, lumaReference, lumaReference, 1.0f);
    }
    else if(debugViewIndex == 2){
        float2 inputInfoViewportSize = _SourceSize.zw;

#if _TJSR_HAS_ACTIVE_PASS
        int2 inputPos = int2(uv * inputInfoViewportSize);
        half depthfactor = Uncompress01ToNegative11(LOAD_TEXTURE2D_X(_TjsrDepthClip, inputPos).x);
#else
    #if _TJSR_PACK_DEPTH_MOTION
        half3 mda = DecodeMotionDepthClip(_TjsrMotionDepthBuffer, uv);
        half depthfactor = mda.z;
    #else
        half depthfactor = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv).z;
    #endif
#endif
        depthfactor = abs(depthfactor);
        outDebugView = half4(depthfactor, depthfactor, depthfactor, 1.0f);
    }
    else if(debugViewIndex == 3){
#if _TJSR_PACK_DEPTH_MOTION
    #if _TJSR_HAS_ACTIVE_PASS
        half2 motion = DecodeMotion(_TjsrMotionDepthBuffer, uv);
    #else
        half2 motion = DecodeMotionDepthClip(_TjsrMotionDepthBuffer, uv).xy;
    #endif
#else
        half2 motion = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_LinearClamp, uv).xy;
#endif
        float2 prevUV = saturate(uv + motion);
        bool isLumaValid = (prevUV.x >= 0.0 && prevUV.y >= 0.0 && prevUV.x <= 1.0 && prevUV.y <= 1.0);
        if (isLumaValid)
        {
#if _TJSR_UINT_INTERMEDIATE
            uint lumaReference32 = FetchUintLuma(uv, int2(0, 0), _TjsrIntermediateColor);
            float lumaReference = UnpackUintToLuma(lumaReference32);
#else
            float lumaReference = GetLuma(SAMPLE_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv).rgb);
#endif
            float3 lumaDiff = UpdateLumaDiff(prevUV, _TjsrLumaHistory, lumaReference);
            float shadingChanged = abs(abs(lumaDiff.y) - abs(lumaDiff.z)) > TJSR_LUMA_THRESHOULD ? 1.0h : 0.0h;
            outDebugView = half4(shadingChanged, shadingChanged, shadingChanged, 1.0f);
        }
        else
        {
            outDebugView = half4(1.0f, 1.0f, 1.0f, 1.0f);
        }
    }
    else{
        outDebugView = half4(0.0f, 0.0f, 0.0f, 1.0f);
    }
}

#endif
