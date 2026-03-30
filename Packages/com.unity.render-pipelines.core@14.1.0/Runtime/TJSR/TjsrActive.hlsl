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

#ifndef TJSR_ACTIVE
#define TJSR_ACTIVE

//#ifndef UNITY_PLATFORM_WEBGL
//    #if SHADER_TARGET < 45
//    #error Tuanjie Super Resolution Shader Active pass requires a shader target of 4.5 or greater
//    #endif
//#endif

#include "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrCommon.hlsl"

#if _TJSR_PACK_DEPTH_MOTION
    TEXTURE2D_X_UINT(_TjsrMotionDepthBuffer);
#else
    TEXTURE2D_X_HALF(_TjsrMotionDepthBuffer);
#endif
#if _TJSR_YCOCG && _TJSR_LUMA_HISTORY
    #if _TJSR_UINT_INTERMEDIATE
    TEXTURE2D_X_UINT(_TjsrIntermediateColor);
    #else
    TEXTURE2D_X(_TjsrIntermediateColor);
    #endif
    TEXTURE2D_X(_TjsrLumaHistory);
#endif


half4 GatherDepth4(float2 uv, int2 offset, TEXTURE2D_X_HALF(inputTexture))
{
#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
    return GATHER_BLUE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * float2(offset));
#else
    half4 samples;
    samples.w = SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * float2(offset + int2(0, 0))).b;
    samples.x = SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * float2(offset + int2(0, 1))).b;
    samples.y = SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * float2(offset + int2(1, 1))).b;
    samples.z = SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * float2(offset + int2(1, 0))).b;
    return samples;
#endif
}

struct DepthNeighbour
{
    //      topleft    topRight.x   topRight.y
    //      btmLeft.y  btmRight.w   btmRight.z
    //      btmLeft.x  btmRight.x   btmRight.y
    half4 btmRight;
    half topleft;
    half2 topRight;
    half2 btmLeft;
};

#if _TJSR_PACK_DEPTH_MOTION
    DepthNeighbour GatherDepth3x3(float2 uv)
    {
        DepthNeighbour data;
    #if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
        data.topleft = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(-1, -1), 0, _SourceSize.zw - 1.0)).r);
        data.btmRight = UnpackDepth(GATHER_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv));
        data.topRight = UnpackDepth(GATHER_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + float2(-_SourceSize.x, 0.0)).xy);
        data.btmLeft = UnpackDepth(GATHER_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + float2(0.0, _SourceSize.y)).yz);
    #else
        data.topleft = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(-1, -1), 0, _SourceSize.zw - 1.0)).r);
        data.btmRight.w = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, uv * _SourceSize.zw).r);
        data.btmRight.x = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(0, 1), 0, _SourceSize.zw - 1.0)).r);
        data.btmRight.y = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(1, 1), 0, _SourceSize.zw - 1.0)).r);
        data.btmRight.z = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(1, 0), 0, _SourceSize.zw - 1.0)).r);
        data.topRight.x = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(0, -1), 0, _SourceSize.zw - 1.0)).r);
        data.topRight.y = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(1, -1), 0, _SourceSize.zw - 1.0)).r);
        data.btmLeft.y = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(-1, 0), 0, _SourceSize.zw - 1.0)).r);
        data.btmLeft.x = UnpackDepth(LOAD_TEXTURE2D_X(_TjsrMotionDepthBuffer, clamp(uv * _SourceSize.zw + int2(-1, 1), 0, _SourceSize.zw - 1.0)).r);
    #endif
        return data;
    }
#else
    DepthNeighbour GatherDepth3x3(float2 uv)
    {
        DepthNeighbour data;
    #if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
        data.topleft = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(-1, -1)).b;
        data.btmRight = GATHER_BLUE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv);
        data.topRight = GATHER_BLUE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + float2(-_SourceSize.x, 0.0)).xy;
        data.btmLeft = GATHER_BLUE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + float2(0.0, _SourceSize.y)).yz;
    #else
        data.topleft = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(-1, -1)).b;
        data.btmRight.w = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv).b;
        data.btmRight.x = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(0, 1)).b;
        data.btmRight.y = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(1, 1)).b;
        data.btmRight.z = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(1, 0)).b;
        data.topRight.x = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(0, -1)).b;
        data.topRight.y = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(1, -1)).b;
        data.btmLeft.y = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(-1, 0)).b;
        data.btmLeft.x = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_PointClamp, uv + _SourceSize.xy * int2(-1, 1)).b;
    #endif
        return data;
    }
#endif

void TjsrActiveFragment(Varyings input
    , out half outDepthClip : SV_Target0
#if _TJSR_LUMA_HISTORY
    , out float2 outLumaHistory : SV_Target1
#endif
	)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

#if _TJSR_PACK_DEPTH_MOTION
    half3 dmv = DecodeMotionDepth(_TjsrMotionDepthBuffer, uv);
    half depth = dmv.x;
    half2 motion = dmv.yz;
#else
    half4 mda = SAMPLE_TEXTURE2D_X(_TjsrMotionDepthBuffer, sampler_LinearClamp, uv);
    half2 motion = mda.xy;
    half depth = mda.z;
#endif
		
    float2 prevUV = saturate(uv + motion);

    half alphaMask = 0.0f;
    half depthClip = 0.0;

    // Compute depth clip from the dilated depth buffer.
    if (depth < 1.0 - 1.0e-05f)
    {
        float2 prevfSample = prevUV * float2(_SourceSize.zw);
        float2 prevfrac = prevfSample - floor(prevfSample);
        float oneMinusPrevfacx = 1.0 - prevfrac.x;

        float bilinweights[4] = {
            oneMinusPrevfacx - oneMinusPrevfacx * prevfrac.y,
            prevfrac.x - prevfrac.x * prevfrac.y,
            oneMinusPrevfacx * prevfrac.y,
            prevfrac.x * prevfrac.y
        };

        float diagonal_length = length(float2(_SourceSize.zw));
        float weightDepth = 0.0;
        float kSep = 1.37e-05f;
        float kFov = _cameraFovAngleHor;
        float kSepFovDiagonal = kSep * kFov * diagonal_length;
        
        DepthNeighbour depthNeighbour = GatherDepth3x3(prevUV);

        half depthTopLeft = min(min(min(depthNeighbour.topleft, depthNeighbour.btmLeft.y), depthNeighbour.topRight.x), depthNeighbour.btmRight.w);
        half depthSep = kSepFovDiagonal * (1.0f - min(depthTopLeft, depth));
        weightDepth += saturate(depthSep / (abs(depthTopLeft - depth) + EPSILON)) * bilinweights[0];

        half depthTopRight = min(min(min(depthNeighbour.btmRight.z, depthNeighbour.topRight.y), depthNeighbour.topRight.x), depthNeighbour.btmRight.w);
        depthSep = kSepFovDiagonal * (1.0f - min(depthTopRight, depth));
        weightDepth += saturate(depthSep / (abs(depthTopRight - depth) + EPSILON)) * bilinweights[1];

        half depthBtmLeft = min(min(min(depthNeighbour.btmLeft.x, depthNeighbour.btmLeft.y), depthNeighbour.btmRight.x), depthNeighbour.btmRight.w);
        depthSep = kSepFovDiagonal * (1.0f - min(depthBtmLeft, depth));
        weightDepth += saturate(depthSep / (abs(depthBtmLeft - depth) + EPSILON)) * bilinweights[2];

        half depthBtmRight = min(min(min(depthNeighbour.btmRight.x, depthNeighbour.btmRight.y), depthNeighbour.btmRight.x), depthNeighbour.btmRight.w);
        depthSep = kSepFovDiagonal * (1.0f - min(depthBtmRight, depth));
        weightDepth += saturate(depthSep / (abs(depthBtmRight - depth) + EPSILON)) * bilinweights[3];

        depthClip = saturate(1.0f - weightDepth);
    }

    // Compute luminance difference from luma history buffer.
#if _TJSR_YCOCG && _TJSR_LUMA_HISTORY
    half reset = _blendFactor < 1 ? 0.0h : 1.0h;
    bool isLumaValid = ((depthClip + reset) < 0.1) && (prevUV.x >= 0.0 && prevUV.y >= 0.0 && prevUV.x <= 1.0 && prevUV.y <= 1.0);
    if (isLumaValid)
    {
        float2 jitteruv;
        jitteruv.x = saturate(uv.x + (_jitterOffset.x * _SourceSize.x));
        jitteruv.y = saturate(uv.y + (_jitterOffset.y * _SourceSize.y));
    #if _TJSR_UINT_INTERMEDIATE
        uint lumaReference32 = FetchUintLuma(jitteruv, int2(0, 0), _TjsrIntermediateColor);
        half lumaReference = UnpackUintToLuma(lumaReference32);
    #else
        half lumaReference = GetLuma(SAMPLE_TEXTURE2D_X(_TjsrIntermediateColor, sampler_LinearClamp, jitteruv).rgb);
    #endif
        //lumaReference = lumaReference * lumaReference;//Gamma20ToLinear
        float3 lumaDiff = UpdateLumaDiff(prevUV, _TjsrLumaHistory, lumaReference);
        bool shadingChanged = abs(abs(lumaDiff.y) - abs(lumaDiff.z)) > TJSR_LUMA_THRESHOULD;
    
    #if defined (HAS_OPAQUE_MASK)
        // Pack output of LumaHistory shading changed into the decimal places of alphaMask.
        alphaMask = floor(alphaMask) + (shadingChanged ? 0.5f : 0.0f);
    #else
        // DepthClip buffer use the highest bit as output of Luma history shading changed.
        if (shadingChanged)
            depthClip = -depthClip;
    #endif
    
        outLumaHistory = CompressNegative11To01(lumaDiff.xy);
    }
    else
    {
        outLumaHistory = float2(0.5h, 0.5h);
    }
#endif

    // Pack DepthClip buffer from {-1, 1} to {0, 1} since DepthClip buffer use R8_UNORM format because R8_SNORM format is not supported in many Mobile devices.
    outDepthClip = CompressNegative11To01Half(depthClip);
}

#endif//TJSR_ACTIVE
