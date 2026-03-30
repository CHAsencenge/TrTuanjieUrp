/**
 * Copyright (c) 2023, Qualcomm Innovation Center, Inc. All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 
 * 3. Neither the name of the copyright holder nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
  *   without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 * 
 * SPDX-License-Identifier: BSD-3-Clause
*/
/*
** Original Author: Snapdragon™ Game Super Resolution, https://github.com/SnapdragonStudios/snapdragon-gsr
*/

#ifndef TJSR_UPSCALE
#define TJSR_UPSCALE

#include "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrCommon.hlsl"
#if (_RCAS || _EASU_RCAS_AND_HDR_INPUT)
#include "Packages/com.unity.render-pipelines.core/Runtime/PostProcessing/Shaders/FSRCommon.hlsl"
#endif


    TEXTURE2D_X_HALF(_TjsrPriorFeedback);
#if _TJSR_PACK_DEPTH_MOTION
    TEXTURE2D_X_UINT(_TjsrMotionDepthBuffer);
#else
    TEXTURE2D_X_HALF(_TjsrMotionDepthBuffer);
#endif
#if _TJSR_HAS_ACTIVE_PASS
    TEXTURE2D_X(_TjsrDepthClip);
#endif
#if _TJSR_YCOCG
    #if _TJSR_UINT_INTERMEDIATE
    TEXTURE2D_X_UINT(_TjsrIntermediateColor);
    #else
    TEXTURE2D_X(_TjsrIntermediateColor);
    #endif
#endif

    static const int2 sampleOffset[9] = {
        int2(+0, +0),

        int2(+0, +1),
        int2(+1, +0),
        int2(-1, +0),
        int2(+0, -1),

        int2(-1, +1),
        int2(+1, -1),
        int2(+1, +1),
        int2(-1, -1)
    };

    struct NeighbourColor
    {
        real3 sampleColor[9];
    };

    NeighbourColor GatherNeighbourColors(float2 uv, int sampleCount)
    {
        NeighbourColor neighbours;
#if _TJSR_YCOCG && _TJSR_UINT_INTERMEDIATE && SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
        uint topleft = FetchUintLuma(uv, int2(-1, -1), _TjsrIntermediateColor);
        uint4 btmRight = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv);
        uint2 topRight = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv + float2(-_SourceSize.x, 0.0)).xy;
        uint2 btmLeft = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv + float2(0.0, _SourceSize.y)).yz;

        neighbours.sampleColor[0] = UnpackUintToR11G11B10Color(btmRight.w);
        neighbours.sampleColor[1] = UnpackUintToR11G11B10Color(btmRight.x);
        neighbours.sampleColor[2] = UnpackUintToR11G11B10Color(btmRight.z);
        neighbours.sampleColor[3] = UnpackUintToR11G11B10Color(btmLeft.y);
        neighbours.sampleColor[4] = UnpackUintToR11G11B10Color(topRight.x);
        neighbours.sampleColor[5] = UnpackUintToR11G11B10Color(btmLeft.x);
        neighbours.sampleColor[6] = UnpackUintToR11G11B10Color(topRight.y);
        neighbours.sampleColor[7] = UnpackUintToR11G11B10Color(btmRight.y);
        neighbours.sampleColor[8] = UnpackUintToR11G11B10Color(topleft);
#else
        UNITY_UNROLL
        for (int i = 0; i < 9; ++i)
        {
            if (i < sampleCount)
            {
    #if _TJSR_YCOCG
        #if _TJSR_UINT_INTERMEDIATE
                uint packColor = FetchUintLuma(uv, sampleOffset[i], _TjsrIntermediateColor);
                neighbours.sampleColor[i] = UnpackUintToR11G11B10Color(packColor);
        #else
                neighbours.sampleColor[i] = SAMPLE_TEXTURE2D_X(_TjsrIntermediateColor, sampler_PointClamp, uv + _SourceSize.xy * sampleOffset[i]).xyz;
        #endif
    #else
                real3 samplecolor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv + _SourceSize.xy * sampleOffset[i]).xyz;
                neighbours.sampleColor[i] = SceneToWorkingSpace(samplecolor);
    #endif
            }
            else
            {
                neighbours.sampleColor[i] = real3(0.0, 0.0, 0.0);
            }
        }
#endif
        return neighbours;
    }

#if _TJSR_YCOCG && _TJSR_UINT_INTERMEDIATE
    struct YCoCgColorNeighbour
    {
        uint4 btmRight;
        uint topleft;
        uint2 topRight;
        uint2 btmLeft;
    };

    YCoCgColorNeighbour GatherYCoCgColor(float2 uv)
    {
        YCoCgColorNeighbour data;
    #if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
        data.topleft = FetchUintLuma(uv, int2(-1, -1), _TjsrIntermediateColor);
        data.btmRight = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv);
        data.topRight = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv + float2(-_SourceSize.x, 0.0)).xy;
        data.btmLeft = GATHER_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, uv + float2(0.0, _SourceSize.y)).yz;
    #else
        data.topleft = FetchUintLuma(uv, int2(-1, -1), _TjsrIntermediateColor);
        data.btmRight.w = FetchUintLuma(uv, int2(0, 0), _TjsrIntermediateColor);
        data.btmRight.x = FetchUintLuma(uv, int2(0, 1), _TjsrIntermediateColor);
        data.btmRight.y = FetchUintLuma(uv, int2(1, 1),  _TjsrIntermediateColor);
        data.btmRight.z = FetchUintLuma(uv, int2(1, 0), _TjsrIntermediateColor);
        data.topRight.x = FetchUintLuma(uv, int2(0, -1), _TjsrIntermediateColor);
        data.topRight.y = FetchUintLuma(uv, int2(1, -1), _TjsrIntermediateColor);
        data.btmLeft.y = FetchUintLuma(uv, int2(-1, 0), _TjsrIntermediateColor);
        data.btmLeft.x = FetchUintLuma(uv, int2(-1, 1), _TjsrIntermediateColor);
    #endif
        return data;
    }
#endif

real FastLanczos(real base)
{
    real y = base - 1.0f;
    real y2 = y * y;
    real y_temp = 0.75f * y + y2;
    return y_temp * y2;
}

void TjsrDoUpscale(Varyings input
    , out real4 outUpscale : SV_Target0
#if _TJSR_DEBUGVIEW
    , out half4 outDebugView : SV_Target1
#endif
    )
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);
    
    float kBiasmaxViewportXScale = min(_ScreenSize.x * _SourceSize.x, 1.99);
    float kScaleFactor = min(20.0, pow((_ScreenSize.x * _SourceSize.x) * (_ScreenSize.y * _SourceSize.y), 3.0));
    float2 kHistoryInfoViewportSizeInverse = _ScreenSize.zw;
    float2 kHistoryInfoViewportSize = _ScreenSize.xy;
    float2 inputJitter = _jitterOffset;
    float2 kInputInfoViewportSize = _SourceSize.zw;
    
    half alphaMask = 0.0f;
    float2 jitteruv;
    jitteruv.x = saturate(uv.x + (inputJitter.x * _SourceSize.x));
    jitteruv.y = saturate(uv.y + (inputJitter.y * _SourceSize.y));
	
    int2 inputPos = int2(jitteruv * kInputInfoViewportSize);
    // Remove the jittering that the projection matrix applies from both sets of coordinates.
    float2 srcpos = float2(inputPos) - inputJitter;
    float2 srcposSrcOutputPos = srcpos - uv * kInputInfoViewportSize;
#if !UNITY_UV_STARTS_AT_TOP
    // Fix the strange blur bug in OpenGL/GL3.
    srcposSrcOutputPos *= 0.5f;
#endif

#if _TJSR_HAS_ACTIVE_PASS
    #if _TJSR_PACK_DEPTH_MOTION
    half2 motion = DecodeMotion(_TjsrMotionDepthBuffer, jitteruv);
    #else
    half3 ma = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_LinearClamp, jitteruv).xyw;
    half2 motion = ma.xy;
    alphaMask = ma.z;
    #endif
    // Unpack DepthClip buffer from {0, 1} to {-1, 1}
    half depthfactor = Uncompress01ToNegative11Half(LOAD_TEXTURE2D_X(_TjsrDepthClip, inputPos).x);
#else
    #if _TJSR_PACK_DEPTH_MOTION
    half3 mda = DecodeMotionDepthClip(_TjsrMotionDepthBuffer, jitteruv);
    #else
    half4 mda = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, jitteruv);
    alphaMask = mda.w;
    #endif
    half2 motion = mda.xy;
    half depthfactor = mda.z;
#endif

    float2 prevUV = saturate(uv + motion);

#if defined (HAS_OPAQUE_MASK)
    half alphab = LOAD_TEXTURE2D_X(_TjsrIntermediateWeights, jitteruv).x;
    half historyValue = frac(alphab); // clamp(alpha, 0.0f, 1.0f);
    alphaMask = (alphab - historyValue) * 0.001f;
    historyValue *= 2.0;
    historyValue += 0.1;
#else
    // Extract luminance shading history from depthfactor.
    half historyValue = depthfactor < 0 ? 1.0f : 0.1;
    depthfactor = abs(depthfactor);
#endif

    real4 history = SAMPLE_TEXTURE2D_X(_TjsrPriorFeedback, sampler_LinearClamp, prevUV);
    real3 historyColor = SceneToWorkingSpace(history).xyz;
#if HAS_OPAQUE_MASK && !_PRESERVE_ALPHA
    half wfactor = max(saturate(abs(history.w)), alphaMask);
#else
    half wfactor = 0.0;
#endif
    // Discard (some) history when outside of history buffer (e.g. camera jump)
    half reset = any(abs(uv - 0.5 + motion) > 0.5) || _blendFactor > 0.99;
    half frameInfluence = 1 - saturate(_blendFactor);
    historyValue *= frameInfluence;
	
    /////upsample and compute box
    real4 upsampledcw = 0.0f;
    half kernelfactor = saturate(wfactor + reset);
    half biasmax = kBiasmaxViewportXScale - kBiasmaxViewportXScale * kernelfactor;
    half biasmin = max(1.0f, 0.3 + 0.3 * biasmax);
    half biasfactor = max(0.25f * depthfactor, kernelfactor);
    half kernelbias = lerp(biasmax, biasmin, biasfactor);
    half motionViewportLen = length(motion * kHistoryInfoViewportSize);
    half curvebias = lerp(-2.0, -3.0, saturate(motionViewportLen * 0.02));

    real3 rectboxcenter = 0.0;
    real3 rectboxvar = 0.0;
    real rectboxweight = 0.0;

    kernelbias *= 0.5f;
    half kernelbias2 = kernelbias * kernelbias;
    int qualityLevel = DecodeQualityLevel(int(_qualityLevel));
    const int sampleCount = (qualityLevel >= 1) ? 9 : 5;

    NeighbourColor neighbours = GatherNeighbourColors(jitteruv, sampleCount);

    real3 rectboxmin = neighbours.sampleColor[0];
    real3 rectboxmax = rectboxmin;

    UNITY_UNROLL
    for (int i = 0; i < sampleCount; ++i)
    {
        real3 samplecolor = neighbours.sampleColor[i];
        real2 baseoffset = srcposSrcOutputPos + sampleOffset[i];
        real baseoffsetDot = dot(baseoffset, baseoffset);
        real base = saturate(baseoffsetDot * kernelbias2);
        real weight = FastLanczos(base);
        upsampledcw += real4(samplecolor * weight, weight);
        real boxweight = exp(baseoffsetDot * curvebias);
        rectboxmin = min(rectboxmin, samplecolor);
        rectboxmax = max(rectboxmax, samplecolor);
        real3 wsample = samplecolor * boxweight;
        rectboxcenter += wsample;
        rectboxvar += (samplecolor * wsample);
        rectboxweight += boxweight;
    }

    rectboxweight = 1.0 / rectboxweight;
    rectboxcenter *= rectboxweight;
    rectboxvar *= rectboxweight;
    rectboxvar = sqrt(abs(rectboxvar - rectboxcenter * rectboxcenter));

    upsampledcw.xyz = clamp(upsampledcw.xyz / upsampledcw.w, rectboxmin-0.005f, rectboxmax+0.005f);
    upsampledcw.w = upsampledcw.w * (1.0f / 3.0f) ;

    real tcontribute = historyValue * saturate(rectboxvar.x * 10.0f);
    real oneMinusWfactor = 1.0f - wfactor;
    tcontribute = tcontribute * oneMinusWfactor;

    real baseupdate = oneMinusWfactor - oneMinusWfactor * depthfactor;
    baseupdate = min(baseupdate, lerp(baseupdate, upsampledcw.w * 10.0f, saturate(10.0f * motionViewportLen)));
    baseupdate = min(baseupdate, lerp(baseupdate, upsampledcw.w, saturate(motionViewportLen * 0.05f)));
    real basealpha = baseupdate;

    real boxscale = max(depthfactor, saturate(motionViewportLen * 0.05f));
    real boxsize = lerp(kScaleFactor, 1.0f, boxscale);
    real3 sboxvar = rectboxvar * boxsize;
    real3 boxmin = rectboxcenter - sboxvar;
    real3 boxmax = rectboxcenter + sboxvar;
    rectboxmax = min(rectboxmax, boxmax);
    rectboxmin = max(rectboxmin, boxmin);

    real3 clampedcolor = clamp(historyColor, rectboxmin, rectboxmax);
    real lerpcontribution = (any(rectboxmin > historyColor) || any(historyColor > rectboxmax)) ? tcontribute : 1.0f;
    lerpcontribution = lerpcontribution - lerpcontribution * sqrt(alphaMask);
    historyColor = lerp(clampedcolor, historyColor, saturate(lerpcontribution));
    real basemin = min(basealpha, 0.1f);
    basealpha = lerp(basemin, basealpha, saturate(lerpcontribution));

    ////blend color
    real alphasum = max(EPSILON, basealpha + upsampledcw.w);
    real alpha = saturate(upsampledcw.w / alphasum + reset);
    upsampledcw.xyz = lerp(historyColor, upsampledcw.xyz, alpha);

    //outHistory = half4(upsampledcw.xyz, wfactor);
    real4 outColor = WorkingSpaceToScene(upsampledcw);

#if _PRESERVE_ALPHA
    #if _TJSR_YCOCG
    wfactor = SAMPLE_TEXTURE2D_X(_TjsrIntermediateColor, sampler_PointClamp, uv + _SourceSize.xy).a;
    #else
    wfactor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv + _SourceSize.xy).a;
    #endif
#endif
    
    outUpscale = real4(outColor.xyz, wfactor);
    
#if _TJSR_DEBUGVIEW
    if(DecodeDebugViewIndex(int(_qualityLevel)) == 4){
        real debugWeight = 1.0f - alpha;
        outDebugView = half4(debugWeight, debugWeight, debugWeight, 0.0f);
    }
    else{
        outDebugView = half4(0.0f, 0.0f, 0.0f, 0.0f);
    }
#endif
}

real4 TjsrDoCopy(Varyings input)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord.xy);

    real4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);

#if (_RCAS || _EASU_RCAS_AND_HDR_INPUT)
    #if _TJSR_YCOCG
    color = real4(YCoCgToRGB(color.xyz), color.w);
    #endif
    int2   positionSS  = uv * _SourceSize.xy;
    FsrRcasH(color.r,
        color.g,
        color.b,
    #if FSR_ENABLE_ALPHA
        color.a,
    #endif
        positionSS,
        FSR_RCAS_CONSTANTS), 1.0);
#else
	color = WorkingSpaceToScene(color);
#endif

#if _ENABLE_ALPHA_OUTPUT
    return max(color, 0.0);
#else
    // NOTE: The compiler should eliminate .w computation since it doesn't affect the output.
    return real4(max(color.xyz, 0.0), 1.0);
#endif
}

#endif//TJSR_UPSCALE
