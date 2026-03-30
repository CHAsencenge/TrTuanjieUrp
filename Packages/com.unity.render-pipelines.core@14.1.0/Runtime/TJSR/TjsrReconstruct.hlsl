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

#ifndef TJSR_RECONSTRUCT
#define TJSR_RECONSTRUCT

#include "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrCommon.hlsl"

    TEXTURE2D_X_HALF(_TjsrMotionVectorTex);
#if _TJSR_LUMA_HISTORY
    TEXTURE2D_X(_TjsrLumaHistory);
#endif

struct TjsrConstructFragmentOutput
{
#if _TJSR_PACK_DEPTH_MOTION
    uint   MotionDepthBuffer : SV_Target0;
#else
    half4  MotionDepthBuffer : SV_Target0;
#endif
#if _TJSR_YCOCG
    #if TJSR_UINT_INTERMEDIATE
    uint   IntermediateColor : SV_Target1;
    #else
    real4  IntermediateColor : SV_Target1;
    #endif
#endif
#if _TJSR_LUMA_HISTORY
    float2  LumaHistory       : SV_Target2;
#endif
};

real4 LinearEyeDepth4(real4 depth, float4 zBufferParam)
{
    return real4(
        LinearEyeDepth(depth.x, zBufferParam),
        LinearEyeDepth(depth.y, zBufferParam),
        LinearEyeDepth(depth.z, zBufferParam),
        LinearEyeDepth(depth.w, zBufferParam)
    );
}

real4 GatherLinearDepth4(float2 uv, int2 offset)
{
    real4 depth4;
#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
    depth4 = GATHER_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(offset));
#else
    depth4.w = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(offset + int2(0, 0))).r;
    depth4.x = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(offset + int2(0, 1))).r;
    depth4.y = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(offset + int2(1, 1))).r;
    depth4.z = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv + _SourceSize.xy * float2(offset + int2(1, 0))).r;
#endif
    depth4 = 1.0 - LinearEyeDepth4(depth4, _ZBufferParams);
    return depth4;
}

TjsrConstructFragmentOutput TjsrReconstructFragment(Varyings input)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    // uv is exactly on input pixel center (x + 0.5, y + 0.5)
    float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

    // texture gather to find nearest depth
    //      a  b  c  d
    //      e  f  g  h
    //      i  j  k  l
    //      m  n  o  p
    //topLeft mnji
    //topRight oplk
    //btmLeft  efba
    //btmRight ghdc

    real4 topLeft = GatherLinearDepth4(uv, int2(-1, -1));
    real4 topRight = GatherLinearDepth4(uv, int2(1, -1));
    real4 btmLeft = GatherLinearDepth4(uv, int2(-1, 1));
    real4 btmRight = GatherLinearDepth4(uv, int2(1, 1));
    
    real bestCenter = min(min(min(topLeft.y, topRight.x), btmLeft.z), btmRight.w);
    real topLeft4 = min(min(min(topLeft.y, topLeft.x), topLeft.z), topLeft.w);
    real topLeftMax9 = min(btmLeft.w, min(min(bestCenter, topLeft4), topRight.w));

    // Find the UV offset of the best depth for MotionVectorMap
    real2 bestOffset = real2(0.0f, 0.0f);
    if (topLeftMax9 <= topLeft.w)
        bestOffset = real2(-1.0f, -1.0f);
    else if(topLeftMax9 <= topLeft.z)
        bestOffset = real2(0.0f, -1.0f);
    else if(topLeftMax9 <= topRight.w)
        bestOffset = real2(1.0f, -1.0f);
    else if(topLeftMax9 <= topLeft.x)
        bestOffset = real2(-1.0f, 0.0f);
    else if(topLeftMax9 <= topRight.x)
        bestOffset = real2(1.0f, 0.0f);
    else if(topLeftMax9 <= btmLeft.w)
        bestOffset = real2(-1.0f, 1.0f);
    else if(topLeftMax9 <= btmLeft.z)
        bestOffset = real2(0.0f, 1.0f);
    else if(topLeftMax9 <= btmRight.w)
        bestOffset = real2(1.0f, 1.0f);

    half2 motion = GetVelocityWithOffset(uv, bestOffset, _TjsrMotionVectorTex);
    float2 prevUV = saturate(uv + motion);

    // Compute depth clip
    half depthClip = 0.0;
    if (bestCenter < 1.0 - 1.0e-05f)
    {
        real topRight4 = min(min(min(topRight.y, topRight.x), topRight.z), topRight.w);
        real btmLeft4 = min(min(min(btmLeft.y, btmLeft.x), btmLeft.z), btmLeft.w);
        real btmRight4 = min(min(min(btmRight.y, btmRight.x), btmRight.z), btmRight.w);

        float kSepFovDiagonal = 1.37e-05f * _cameraFovAngleHor * length(_SourceSize.zw);
        float depthSep = kSepFovDiagonal * (1.0 - bestCenter);
        float weightDepth = 0.0;
        weightDepth += saturate((depthSep / (abs(bestCenter - topLeft4) + EPSILON)));
        weightDepth += saturate((depthSep / (abs(bestCenter - topRight4) + EPSILON)));
        weightDepth += saturate((depthSep / (abs(bestCenter - btmLeft4) + EPSILON)));
        weightDepth += saturate((depthSep / (abs(bestCenter - btmRight4) + EPSILON)));
        depthClip = saturate(1.0f - weightDepth * 0.25);
    }
    
    TjsrConstructFragmentOutput output;
    
    real alphaMask = real(0.0f);
#if _TJSR_YCOCG
    // Generate color in ycocg space
    real4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
    real4 workingCol = SceneToWorkingSpace(col);
    #if defined (HAS_OPAQUE_MASK)
    real4 opaqueCol = SAMPLE_TEXTURE2D_X(_BlitOpaqueTexture, sampler_PointClamp, uv);
    real4 opaqueWorkingCol = SceneToWorkingSpace(opaqueCol);
    real4 delta = abs(workingCol - opaqueWorkingCol);
    alphaMask = max(delta.x, max(delta.y, delta.z));
    alphaMask = (0.35f * 1000.0f) * alphaMask;
    #endif

    // Compute luminance difference from luma history buffer.
#if _TJSR_LUMA_HISTORY
    half reset = _blendFactor < 1 ? 0.0h : 1.0h;
    bool isLumaValid = ((depthClip + reset) < 0.1) && (prevUV.x >= 0.0 && prevUV.y >= 0.0 && prevUV.x <= 1.0 && prevUV.y <= 1.0);
    if (isLumaValid)
    {
        float3 lumaDiff = UpdateLumaDiff(prevUV, _TjsrLumaHistory, GetLuma(workingCol.rgb));
        bool shadingChanged = abs(abs(lumaDiff.y) - abs(lumaDiff.z)) > TJSR_LUMA_THRESHOULD;

    #if defined (HAS_OPAQUE_MASK)
        // Pack output of LumaHistory shading changed into the decimal places of alphamask.
        alphaMask = floor(alphaMask) + (shadingChanged ? 0.5f : 0.0f);
    #else
        // DepthClip buffer use the highest bit as output of Luma history shading changed.
        if (shadingChanged)
            depthClip = -depthClip;
    #endif

        output.LumaHistory = CompressNegative11To01(lumaDiff.xy);
    }
    else
    {
        output.LumaHistory = float2(0.5h, 0.5h);
    }
#endif

    #if TJSR_UINT_INTERMEDIATE
    output.IntermediateColor = PackR11G11B10ColorToUint(workingCol.rgb);
    #else
    output.IntermediateColor = workingCol;
    #endif
#endif//_TJSR_YCOCG

#if _TJSR_PACK_DEPTH_MOTION
    // Pack {LSB 8-bit depth, MSB 12-bit XY motion}.
    output.MotionDepthBuffer = PackMvDc(half3(motion, depthClip));
#else
    output.MotionDepthBuffer = real4(motion, depthClip, alphaMask);
#endif
    return output;
}

#endif//TJSR_RECONSTRUCT
