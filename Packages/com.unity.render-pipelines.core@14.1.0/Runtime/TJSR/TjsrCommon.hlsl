#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

    #define EPSILON 1.19e-07f

    int DecodeQualityLevel(int param)
    {
        return param & 0xFF;
    }

    int DecodeDebugViewIndex(int param)
    {
        return (param >> 8) & 0xFF;
    }

    // Per-pixel camera backwards velocity
    half2 GetVelocityWithOffset(float2 uv, real2 depthOffsetUv, TEXTURE2D_X_HALF(inputTexture))
    {
        // Unity motion vectors are forward motion vectors in screen UV space
        half2 offsetUv = SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, uv + _SourceSize.xy * depthOffsetUv).xy;
        return -offsetUv;
    }

    void AdjustBestDepthOffset(inout real bestDepth, inout half bestX, inout half bestY, float2 uv, half currX, half currY)
    {
        // Half precision should be fine, as we are only concerned about choosing the better value along sharp edges, so it's
        // acceptable to have banding on continuous surfaces
        real depth = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_PointClamp, uv.xy + _SourceSize.xy * half2(currX, currY)).r;

    #if UNITY_REVERSED_Z
        depth = 1.0 - depth;
    #endif

        bool isBest = depth < bestDepth;
        bestDepth = isBest ? depth : bestDepth;
        bestX = isBest ? currX : bestX;
        bestY = isBest ? currY : bestY;
    }

    float Uncompress01ToNegative11(float v01)
    {
        return v01 * 2.0f - 1.0f;
    }

    float CompressNegative11To01(float v11)
    {
        return v11 * 0.5f + 0.5f;
    }

    float2 Uncompress01ToNegative11(float2 v01)
    {
        return v01 * 2.0f - 1.0f;
    }

    float2 CompressNegative11To01(float2 v11)
    {
        return v11 * 0.5f + 0.5f;
    }

    half Uncompress01ToNegative11Half(half v01)
    {
        return v01 * 2.0h - 1.0h;
    }

    half CompressNegative11To01Half(half v11)
    {
        return v11 * 0.5h + 0.5h;
    }

    half2 Uncompress01ToNegative11Half(half2 v01)
    {
        return v01 * 2.0h - 1.0h;
    }

    half2 CompressNegative11To01Half(half2 v11)
    {
        return v11 * 0.5h + 0.5h;
    }


    real GetLuma(real3 color)
    {
#if _TJSR_YCOCG
        // We work in YCoCg hence the luminance is in the first channel.
        return color.x;
#else
        return Luminance(color.xyz);
#endif
    }

    // Working Space: The color space that we will do the calculation in.
    // Scene: The incoming/outgoing scene color. Either linear or gamma space
    real3 SceneToWorkingSpace(real3 src)
    {
#if _GAMMA_20 && !UNITY_COLORSPACE_GAMMA
    #ifdef HDR_INPUT
        // In HDR output mode, the colors are expressed in nits, which can go up to 10k nits.
        // We divide by the display max nits to get a max value closer to 1.0 but it could still be > 1.0.
        // Finally, use FastTonemap() to squash everything < 1.0.
        src = FastTonemap(src * OneOverPaperWhite);
    #endif
        // TJSR expects perceptually encoded color data so either encode to gamma 2.0 here if the input
        // data is linear, or let it pass through unchanged if it's already gamma encoded.
        src = LinearToGamma20(src);
#endif

#if _TJSR_YCOCG
        real3 dst = RGBToYCoCg(src.xyz);
#else
        real3 dst = src;
#endif
        return dst;
    }

    real4 SceneToWorkingSpace(real4 src)
    {
        return real4(SceneToWorkingSpace(src.rgb), src.a);
    }

    real4 WorkingSpaceToScene(real4 src)
    {
#if _TJSR_YCOCG
        real4 dst = real4(abs(YCoCgToRGB(src.xyz)), src.w);
#else
        real4 dst = src;
#endif

#if _GAMMA_20 && !UNITY_COLORSPACE_GAMMA
        dst = Gamma20ToLinear(dst);
    #ifdef HDR_INPUT
        dst = FastTonemapInvert(dst) * PaperWhite;
    #endif
#endif
        return dst;
    }

    uint PackR11G11B10ColorToUint(real3 color)
    {
        uint r11 = uint(round(color.x * 2047.5));
        uint g11 = uint(round(color.y * 2047.5));
        uint b10 = uint(round(color.z * 1023.5));
        return uint((r11 << 21u) | (g11 << 10u) | b10);
    }

    real UnpackUintToLuma(uint pack)
    {
	    uint x11 = pack >> 21u;
        return real(x11) * 4.884e-4;//(1.0 / 2047.5)
    }
    
    real3 UnpackUintToR11G11B10Color(uint pack)
    {
        uint r11 = pack >> 21u;
        uint g11 = (pack & (2047u << 10u)) >> 10u;
        uint b10 = pack & 1023u;
        real3 color;
        color.x = float(r11) * 4.884e-4;//* (1.0 / 2047.5)
        color.y = float(g11) * 4.884e-4;//* (1.0 / 2047.5) >> 10 - 0.5
        color.z = float(b10) * 9.77e-4;//* (1.0 / 1023.5) - 0.5

        return color;
    }

#if _TJSR_UINT_INTERMEDIATE
    uint FetchUintLuma(float2 coords, int2 offset, TEXTURE2D_X_UINT(inputTexture))
    {
        return LOAD_TEXTURE2D_X(inputTexture, clamp(coords * _SourceSize.zw + offset, 0, _SourceSize.zw - 1.0)).r;
    }
#endif

#if TJSR_PACK_UINT
    // Custom implementation of f32tof16 and f16tof32 for older shader models
    uint f32tof16_custom(float val)
    {
        uint f32 = asuint(val);
        uint f16 = 0;
    
        // Extract components
        uint sign = (f32 >> 31) & 0x1;
        uint exp = (f32 >> 23) & 0xFF;
        uint mantissa = f32 & 0x7FFFFF;
    
        if (exp == 0)
        {
            // Zero or denormal
            f16 = (sign << 15);
        }
        else if (exp == uint(0xFF))
        {
            // Infinity or NaN
            f16 = (sign << 15) | (0x1F << 10) | (mantissa ? 0x200 : 0);
        }
        else
        {
            // Normalized number
            int newexp = int(exp) - 127 + 15;
            if (newexp < 0)
            {
                // Underflow to zero
                f16 = (sign << 15);
            }
            else if (newexp > 31)
            {
                // Overflow to infinity
                f16 = (sign << 15) | (0x1F << 10);
            }
            else
            {
                // Regular number
                f16 = (sign << 15) | (uint(newexp) << 10) | (mantissa >> 13);
            }
        }
    
        return f16;
    }

    float f16tof32_custom(uint val)
    {
        if (val == 0) return 0.0f;
    
        // Extract components
        uint sign = (val >> 15) & 0x1;
        uint exp = (val >> 10) & 0x1F;
        uint mantissa = val & 0x3FF;
    
        // Convert to float32 format
        uint f32 = 0;
    
        if (exp == 0)
        {
            if (mantissa == 0)
            {
                // Zero
                f32 = sign << 31;
            }
            else
            {
                // Denormal
                exp = 0x1C3 - uint(firstbithigh(mantissa));
                mantissa = (mantissa << (24 - uint(firstbithigh(mantissa)))) & 0x7FFFFF;
                f32 = (sign << 31) | (exp << 23) | mantissa;
            }
        }
        else if (exp == uint(0x1F))
        {
            // Infinity or NaN
            f32 = (sign << 31) | (0xFF << 23) | (mantissa << 13);
        }
        else
        {
            // Normalized number
            f32 = (sign << 31) | ((exp + 112) << 23) | (mantissa << 13);
        }
    
        return asfloat(f32);
    }

    // Helper function for f16tof32_custom
    int firstbithigh(uint value)
    {
        int result = 0;
        while (value >>= 1)
        {
            result++;
        }
        return result;
    }

    uint PackLumaHistoryToUint(half2 luma)
    {
#if (SHADER_TARGET >= 45)
        return (f32tof16(luma.x) << 16u) | f32tof16(luma.y);
#else
        return (f32tof16_custom(luma.x) << 16u) | f32tof16_custom(luma.y);
#endif
    }

    half2 UnpackLumaHistory(uint pack)
    {
#if (SHADER_TARGET >= 45)
        return half2(f16tof32(pack >> 16u), f16tof32(pack & 0xFFFF));
#else
        return half2(f16tof32_custom(pack >> 16u), f16tof32_custom(pack & 0xFFFF));
#endif
    }
#endif//TJSR_PACK_UINT

    #define TJSR_LUMA_THRESHOULD 0.008 // {-128, 128} mapping precision

    float3 UpdateLumaDiff(float2 PrevUV
#if TJSR_PACK_UINT
        , TEXTURE2D_X_UINT(inputTexture)
#else
        , TEXTURE2D_X(inputTexture)
#endif
        , half luma_reference)
    {
        float2 current_luma_diff;
#if TJSR_PACK_UINT
        uint prev_luma_diff_pack = FetchUintLuma(PrevUV, int2(0, 0), inputTexture);
        float2 prev_luma_diff = UnpackLumaHistory(prev_luma_diff_pack);
#else
        float2 prev_luma_diff = Uncompress01ToNegative11(SAMPLE_TEXTURE2D_X(inputTexture, sampler_LinearClamp, PrevUV).xy);
#endif

        float luma_diff = luma_reference - prev_luma_diff.x;
        current_luma_diff.x = luma_reference;
        current_luma_diff.y = (abs(prev_luma_diff.y) > TJSR_LUMA_THRESHOULD) ? 
                ((sign(luma_diff) == sign(prev_luma_diff.y)) ? 
                (sign(luma_diff) * min(abs(prev_luma_diff.y), abs(luma_diff))) : 
                prev_luma_diff.y) : 
                luma_diff;
        
        return float3(current_luma_diff, luma_diff);
    }


    uint TjsrBfeU1(uint src, uint off, uint bits)
    {
        //GLSL: return bitfieldExtract(src, int(off), int(bits));
        uint msk = (1u << bits) - 1;
        return (src >> off) & msk;
    }
    uint TjsrBfiMskU1(uint src, uint ins, uint bits)
    {
        uint msk = (1u << bits) - 1;
        return (ins & msk) | (src & (~msk));
    }
    // Make {<+0 := -1.0, >=+0 := 1.0}.
    half TjsrSgnOneF1(half x) { return asfloat(TjsrBfiMskU1(asuint(float(x)), 0x3f800000, 31)); }
    half TjsrCpySgnF1(half d, half s) { return asfloat(TjsrBfiMskU1(asuint(float(s)), asuint(float(d)), 31)); }
    half2 TjsrCpySgnF2(half2 d, half2 s) { return half2(TjsrCpySgnF1(d.x, s.x), TjsrCpySgnF1(d.y, s.y)); }

    // Pack MotionVector ranging in {-1 to 1} to 11bits and depth ranging in {0 to 1} to 10bits.
    uint PackMvDepth(half2 v, half z)
    {
        // {-1 to 1} linear to gamma 2.0 {-1 to 1}
        v = TjsrCpySgnF2(sqrt(abs(v)), v);
        // Limit to {-1024/1024 to 1023/1024}.
        v = min(v, half2(1023.0h / 1024.0h, 1023.0h / 1024.0h));
        // Encode to 11-bit with zero at center of one step.
        v = v * 1024.0h + 1024.0h;
        // Pack.
        return (asuint((float)z * 1023.0f) << 22) + (asuint((float)v.y) << 11) + asuint((float)v.x);
    }

    // Unpack MotionVector  ranging in {-1 to 1} and depth ranging in {0 to 1}.
    half3 UnpackMvDepth(uint packed)
    {
        half3 md;
        uint iz = TjsrBfeU1(packed, 22u, 10u);
        uint iy = TjsrBfeU1(packed, 11u, 11u);
        uint ix = TjsrBfeU1(packed, 0, 11u);
        md.z = asfloat(iz) * (1.0h / 1023.0h);
        md.y = asfloat(iy) * (1.0h / 1024.0h) - 1.0h;
        md.x = asfloat(ix) * (1.0h / 1024.0h) - 1.0h;
        md.xy *= abs(md.xy);
        return md;
    }

    // Unpack just velocity.
    half2 UnpackMv(uint i)
    {
        uint iy = TjsrBfeU1(i, 11u, 11u);
        uint ix = TjsrBfeU1(i, 0, 11u);
        half2 v;
        v.y = asfloat(iy) * (1.0h / 1024.0h) - 1.0h;
        v.x = asfloat(ix) * (1.0h / 1024.0h) - 1.0h;
        v *= abs(v);
        return v;
    }

    // Unpack just depth.
    half UnpackDepth(uint packed)
    {
        uint iz = TjsrBfeU1(packed, 22u, 10u);
        return asfloat(iz) * (1.0h / 1023.0h);
    }

    half2 UnpackDepth(uint2 packed)
    {
        return half2(UnpackDepth(packed.x), UnpackDepth(packed.y));
    }

    half4 UnpackDepth(uint4 packed)
    {
        return half4(UnpackDepth(packed.x), UnpackDepth(packed.y), UnpackDepth(packed.z), UnpackDepth(packed.w));
    }

    // Pack MotionVector to 12bits and DepthClip to 8bits both ranging in {-1 to 1}.
    uint PackMvDc(half3 mz)
    {
        // {-1 to 1} linear to gamma 2.0 {-1 to 1}
        //mz.xy = TjsrCpySgnF2(sqrt(abs(mz.xy)), mz.xy);
        half2 mv = sqrt(abs(mz.xy));
        mz.x = mz.x < 0 ? -mv.x : mv.x;
        mz.y = mz.y < 0 ? -mv.y : mv.y;
        // Map to [0,1]
        mz = saturate(mz * 0.5h + 0.5h);

        uint mvx = uint(round(mz.x * 4095.0h + 0.5h)); // 12 bits
        uint mvy = uint(round(mz.y * 4095.0h + 0.5h)); // 12 bits
        uint dc = uint(round(mz.z * 255.0h + 0.5h)); // 8 bits
    
        return (mvx << 20) | (mvy << 8) | dc;
    }

    // Unpack MotionVector and DepthClip ranging in {-1 to 1}.
    half3 UnpackMvDc(uint packed)
    {
        half3 md;
        md.x = half(packed >> 20) * (2.0h / 4095.0h) - 1.0h;
        md.y = half((packed >> 8) & 4095) * (2.0h / 4095.0h) - 1.0h;
        md.z = half(packed & 255) * (2.0h / 255.0h) - 1.0h;
    
        md.xy *= abs(md.xy);
        return md;
    }

#if _TJSR_PACK_DEPTH_MOTION
    half3 DecodeMotionDepth(TEXTURE2D_X_UINT(inputTexture), float2 coords)
    {
//#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
//        uint4 packed4 = GATHER_RED_TEXTURE2D_X(inputTexture, sampler_PointClamp, coords);
//        uint packed = min(min(min(packed4.x, packed4.y), packed4.z), packed4.w);
//#else
        uint packed = LOAD_TEXTURE2D_X(inputTexture, coords * _SourceSize.zw).r;
//#endif
        return UnpackMvDepth(packed);
    }

    half2 DecodeMotion(TEXTURE2D_X_UINT(inputTexture), float2 coords)
    {
//#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
//        uint4 packed4 = GATHER_RED_TEXTURE2D_X(inputTexture, sampler_PointClamp, coords);
//        uint packed = min(min(min(packed4.x, packed4.y), packed4.z), packed4.w);
//#else
        uint packed = LOAD_TEXTURE2D_X(inputTexture, coords * _SourceSize.zw).r;
//#endif
        return UnpackMv(packed);
    }

    half3 DecodeMotionDepthClip(TEXTURE2D_X_UINT(inputTexture), float2 coords)
    {
//#if SHADER_TARGET >= 45 && defined(PLATFORM_SUPPORT_GATHER)
//        uint4 zvpn4 = GATHER_RED_TEXTURE2D_X(inputTexture, sampler_PointClamp, coords);
//        uint zvpn = min(min(min(zvpn4.x, zvpn4.y), zvpn4.z), zvpn4.w);
//#else
        uint zvpn = LOAD_TEXTURE2D_X(inputTexture, coords * _SourceSize.zw).r;
//#endif
        return UnpackMvDc(zvpn);
    }
#endif//_TJSR_PACK_DEPTH_MOTION
