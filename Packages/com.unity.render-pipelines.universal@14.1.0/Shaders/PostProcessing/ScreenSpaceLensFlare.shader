Shader "Hidden/Universal Render Pipeline/ScreenSpaceLensFlare"
{
    HLSLINCLUDE
        #pragma exclude_renderers gles
        #pragma multi_compile_local _ _USE_RGBM

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ScreenCoordOverride.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Filtering.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
        #include_with_pragmas "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRenderingKeywords.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRendering.hlsl"

        real4 _ScreenSpaceLensFlare_Params1;
        real4 _ScreenSpaceLensFlare_Params2;
        real4 _ScreenSpaceLensFlare_Params3;
        real4 _ScreenSpaceLensFlare_Params4;
        real4 _ScreenSpaceLensFlare_Params5;
        real3 _ScreenSpaceLensFlare_TintColor;

        real _ScreenSpaceLensFlare_MipLevel;

        TEXTURE2D_X(_ScreenSpaceLensFlare_GlareTexture);
        float4 _ScreenSpaceLensFlare_GlareTexture_TexelSize;
        float4 _BlitTexture_TexelSize;

        #define Intensity _ScreenSpaceLensFlare_Params1.x
        #define RegularMultiplier _ScreenSpaceLensFlare_Params1.y
        #define ReverseMultiplier _ScreenSpaceLensFlare_Params1.z
        #define HaloMultiplier _ScreenSpaceLensFlare_Params1.w

        #define HaloScaleX _ScreenSpaceLensFlare_Params2.x
        #define HaloScaleY _ScreenSpaceLensFlare_Params2.y
        #define SampleCount _ScreenSpaceLensFlare_Params2.z
        #define SampleDimmer _ScreenSpaceLensFlare_Params2.w

        #define StartingPoint _ScreenSpaceLensFlare_Params3.x
        #define GhostScale _ScreenSpaceLensFlare_Params3.y
        #define VignetteScale real2(_ScreenSpaceLensFlare_Params3.z,_ScreenSpaceLensFlare_Params3.w)

        #define VignetteIntensity _ScreenSpaceLensFlare_Params4.x
        #define ChromaticIntensity _ScreenSpaceLensFlare_Params4.y
        #define GlareMultiplier _ScreenSpaceLensFlare_Params4.z

        #define GlareLength _ScreenSpaceLensFlare_Params5.x
        #define GlareOrientation float2(_ScreenSpaceLensFlare_Params5.y, _ScreenSpaceLensFlare_Params5.z)
        #define GlareThreshold _ScreenSpaceLensFlare_Params5.w

        #define SQRT_2 1.414
        #define INV_12 0.083
        #define INV_6  0.167
        #define INV_4  0.250
        #define INV_2  0.500
        static const half3 ColorChannels[3] = { 
            half3(1.0h, 0.0h, 0.0h), 
            half3(0.0h, 1.0h, 0.0h), 
            half3(0.0h, 0.0h, 1.0h) 
        };

        float map01To(float value, float min, float max)
        {
            return (max - min) * (value - 0.5);
        }

        float map01(float value, float min, float max)
        {
            float r = rcp(max - min);
            return Remap01(value, r, min * r);
        }

        half4 EncodeHDR(half3 color)
        {
            #if _USE_RGBM
                half4 outColor = EncodeRGBM(color);
            #else
                half4 outColor = half4(color, 1.0);
            #endif

            #if UNITY_COLORSPACE_GAMMA
                return half4(sqrt(outColor.xyz), outColor.w); // linear to γ
            #else
                return outColor;
            #endif
        }

        half3 DecodeHDR(half4 color)
        {
            #if UNITY_COLORSPACE_GAMMA
                color.xyz *= color.xyz; // γ to linear
            #endif

            #if _USE_RGBM
                return DecodeRGBM(color);
            #else
                return color.xyz;
            #endif
        }

        // Ensure the uv is within the valid([0,1]) texture coordinate range.
        // Apply smooth boundary masking using double smoothstep.
        // Transition range: UV [0.0, 0.2] for fade-in, [0.8, 1.0] for fade-out -> avoiding hard discontinuities from UV clamping.
        real CalculateMask(float2 uv)
        {
            real2 edgeMask = smoothstep(float2(0.0, 0.0), 0.2, uv) * smoothstep(float2(1.0, 1.0), 0.8, uv);
            return edgeMask.x * edgeMask.y;
        }

        float2 ClampAndScaleUVForBilinear(float2 uv)
        {
            float2 maxCoord = 1.0 - 0.5 * _ScreenSize.zw;
            return min(uv, maxCoord);
        }

        half3 SampleColor(bool chromaticAberrationEnabled, TEXTURE2D_X_PARAM(tex, samplerTex), float2 uv, float2 diff)
        {
            UNITY_BRANCH if(chromaticAberrationEnabled)
            {
                half r = DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv)))).r;
                half g = DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv + diff)))).g;
                half b = DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv + 2.0 * diff)))).b;
                return half3(r, g, b);
            }
            else
            {
                return DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv))));
            }           
        }

        float2 ComputeHaloUV(float2 uv, real scale)
        {
            float2 sampleUV = float2(HaloScaleX * map01To(uv.x, -scale, scale), HaloScaleY * map01To(uv.y, -scale, scale));
            float x = SafeSqrt(SafePositivePow(sampleUV.x, 2) + SafePositivePow(sampleUV.y, 2));
            // 1.41 = sqrt(2.0)
            float x1 = map01(x, 0.0, SQRT_2);
            float y = FastAtan2(sampleUV.x, sampleUV.y);
            float y1 = 1.0 - map01(y, -PI, PI);
            sampleUV = float2(y1, 1.0 - x1);
            return sampleUV;
        }

        half3 SampleColorHalo(bool chromaticAberrationEnabled, TEXTURE2D_X_PARAM(tex, samplerTex), float2 uv, float2 diff, real scale)
        {
            half3 color = {0.0, 0.0, 0.0};
            float2 UVs[3];
            UNITY_BRANCH if(chromaticAberrationEnabled)
            {
                [unroll(3)]
                for (uint i = 0; i < 3; i++)
                {
                    UVs[i] = uv + i * diff;
                }

                [unroll(3)]
                for (uint j = 0; j < (uint)3; j++)
                {
                    float2 sampleUV = ComputeHaloUV(UVs[j], scale);
                    real mask = CalculateMask(sampleUV);
                    color += DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(sampleUV)))) * ColorChannels[j] * mask;
                }
            }
            else
            {
                float2 sampleUV = ComputeHaloUV(uv, scale);
                real mask = CalculateMask(sampleUV);
                color = DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(sampleUV)))) * mask;
            }

            return color;
        }

        half3 SampleBlurDown(TEXTURE2D_X_PARAM(tex, samplerTex), float2 uv)
        {
            real mask = all(step(0, uv) * step(uv, 1));
            return mask * DecodeHDR(SAMPLE_TEXTURE2D_X(tex, samplerTex, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv))));
        }

        half4 FragGlarePrefilter(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // Glares Prefilter
            float2 orientation = GlareOrientation * _BlitTexture_TexelSize.xy;
            half3 color = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv + orientation)))) * 0.5;
            color += DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv - orientation)))) * 0.5;
            real br = max(color.r, max(color.g, color.b));
            color *= max(br - GlareThreshold, 0.0) / max(br, 1e-4);

            return EncodeHDR(color);
        }

        half4 FragGlareBlurDown(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // Glares Blur
            float2 orientation = GlareOrientation * _BlitTexture_TexelSize.xy * GlareLength * _ScreenSpaceLensFlare_MipLevel;
            half3 color = SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv + orientation) * INV_4;
            color += SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv + 3.0 * orientation) * INV_6;
            color += SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv + 5.0 * orientation) * INV_12;
            color += SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv - orientation) * INV_4;
            color += SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv - 3.0 * orientation) * INV_6;
            color += SampleBlurDown(TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), uv - 5.0 * orientation) * INV_12;

            return EncodeHDR(color);
        }

        half4 FragGlareBlurUp(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // Glares Blur
            float2 orientation = GlareOrientation * _BlitTexture_TexelSize.xy * GlareLength * _ScreenSpaceLensFlare_MipLevel;
            half3 color = DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv)))) * INV_2;
            color += DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv + orientation)))) * INV_4;
            color += DecodeHDR(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, ClampAndScaleUVForBilinear(SCREEN_COORD_REMOVE_SCALEBIAS(uv - orientation)))) * INV_4;

            return EncodeHDR(color);
        }

        half4 FragComposition(Varyings input) : SV_Target
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
            float2 uv = UnityStereoTransformScreenSpaceTex(input.texcoord);

            // Setup common variables
            half3 color = half3(0.0, 0.0, 0.0);
            float2 CenterToUV = uv - 0.5;
            float CenterToUVLength = length(CenterToUV);

            // If the chormatic aberration is enabled.
            bool chromaticAberrationEnabled = ChromaticIntensity > 0.0;
            // UV offset between channels.
            float2 coords = 2.0 * CenterToUV;
            float2 end = uv - coords * dot(coords, coords) * ChromaticIntensity;
            float2 diff = (end - uv) / 3.0;
            real haloSign = sign(0.5 - uv.y);

            // Compute Vignette Effect
            real vignetteRound = length(CenterToUV * VignetteScale) * 2;
            vignetteRound = vignetteRound * vignetteRound;
            vignetteRound = saturate(vignetteRound * vignetteRound);
            vignetteRound = lerp(1, vignetteRound, VignetteIntensity);

            // First ghost uv.
            float2 startingPointUV = CenterToUV * rcp(StartingPoint) + 0.5;
            float2 sampleUV = startingPointUV;

            // Draw maximum three flares.
            [unroll(3)] for (uint i = 0; i < (uint)SampleCount; i++)
            {
                // Setup parameters
                float currentSampleDimmer = SafePositivePow(SampleDimmer, i);
                real scale = rcp(SafePositivePow(i + 1, GhostScale));

                // Compute the (reverse) Ghost flares.
                // The variable "mask" masks out invalid sampling artifacts caused by out-of-bounds UV coordinates, when the "sampleUV" exceeds the valid([0,1]) texture coordinate range.
                sampleUV = startingPointUV;
                sampleUV = (sampleUV - 0.5) * scale + 0.5;
                real mask = CalculateMask(sampleUV);
                // Create Ghost flares.
                color += SampleColor(chromaticAberrationEnabled, TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), sampleUV, diff) * RegularMultiplier * currentSampleDimmer * mask;

                sampleUV = 1.0 - sampleUV;
                mask = CalculateMask(sampleUV);
                // Create reverse Ghost flares.
                color += SampleColor(chromaticAberrationEnabled, TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), sampleUV, -diff) * ReverseMultiplier * currentSampleDimmer * mask;

                // Create Halo flares.
                color += SampleColorHalo(chromaticAberrationEnabled, TEXTURE2D_X_ARGS(_BlitTexture, sampler_LinearClamp), startingPointUV, diff, scale) * HaloMultiplier * currentSampleDimmer * mask;
            }

            // Apply Vignette
            color *= vignetteRound;

            // Ghost + Glare
            color += SampleColor(chromaticAberrationEnabled, TEXTURE2D_X_ARGS(_ScreenSpaceLensFlare_GlareTexture, sampler_LinearClamp), uv, diff) * GlareMultiplier;
            
            return EncodeHDR(color * _ScreenSpaceLensFlare_TintColor * Intensity);
        }
    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Glare Prefilter"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragGlarePrefilter
            ENDHLSL
        }

        Pass
        {
            Name "Glare BlurDown"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragGlareBlurDown
            ENDHLSL
        }

        Pass
        {
            Name "Glare BlurUp"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragGlareBlurUp
            ENDHLSL
        }

        Pass
        {
            Name "Composition"
                        
            Blend One One
            BlendOp Add, Max

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragComposition
            ENDHLSL
        }
    }
}
