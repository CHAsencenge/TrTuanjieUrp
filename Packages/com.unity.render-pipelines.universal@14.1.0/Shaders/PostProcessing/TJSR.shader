Shader "Hidden/Universal Render Pipeline/TJSR"
{
    HLSLINCLUDE
        #pragma multi_compile _ _USE_DRAW_PROCEDURAL
        #pragma multi_compile_local_fragment _ HDR_INPUT

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

        // UINT texture sampler is not supported in GLES2.
        #if _TJSR_HAS_ACTIVE_PASS || defined(SHADER_API_GLES)
            #define _TJSR_PACK_DEPTH_MOTION 0
        #else
            #define _TJSR_PACK_DEPTH_MOTION 1
        #endif

        #if _TJSR_INTERMEDIATE_COLOR
            #define _TJSR_YCOCG 1
            #define _TJSR_LUMA_HISTORY 1
        #else
            // Use RGB color space for better perf. on low-end devices.
            #define _TJSR_YCOCG 0
            #define _TJSR_LUMA_HISTORY 0
        #endif

        #ifndef _GAMMA_20
        #define _GAMMA_20 1
        #endif

        float4 _SourceSize;   // (1/w, 1/h, w, h)
        float4 _HDROutputLuminanceParams;
        float2 _jitterOffset;
        float _cameraFovAngleHor;//Horizontal camera hFov
        half _blendFactor;
        half _qualityLevel;

        #define PaperWhite _HDROutputLuminanceParams.z
        #define OneOverPaperWhite _HDROutputLuminanceParams.w
    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        LOD 100
        ZTest Always ZWrite Off Blend Off Cull Off
        
        Pass
        {
            Name "TJSR - Upscale"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment TjsrDoUpscale

                #pragma multi_compile_local_fragment _ _PRESERVE_ALPHA
                #pragma multi_compile_local_fragment _ _TJSR_DEBUGVIEW
                #pragma multi_compile_local_fragment _ _TJSR_HAS_ACTIVE_PASS
                #pragma multi_compile_local_fragment _ _TJSR_INTERMEDIATE_COLOR

                #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrUpscale.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "TJSR - Setup"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment TjsrSetupFragment

                #ifndef UNITY_PLATFORM_WEBGL
                    #pragma target 4.5
                #endif

                #ifdef _TJSR_YCOCG
                #undef _TJSR_YCOCG
                #endif
                #define _TJSR_YCOCG 1

                #ifdef _TJSR_PACK_DEPTH_MOTION
                #undef _TJSR_PACK_DEPTH_MOTION
                #endif
                #define _TJSR_PACK_DEPTH_MOTION 0

                #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrSetup.hlsl"
            ENDHLSL
        }
		
		Pass
        {
            Name "TJSR - Active"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment TjsrActiveFragment
                
                #ifndef UNITY_PLATFORM_WEBGL
                    #pragma target 4.5
                #endif

                #ifdef _TJSR_YCOCG
                #undef _TJSR_YCOCG
                #endif
                #define _TJSR_YCOCG 1

                #ifdef _TJSR_LUMA_HISTORY
                #undef _TJSR_LUMA_HISTORY
                #endif
                #define _TJSR_LUMA_HISTORY 1

                #ifdef _TJSR_PACK_DEPTH_MOTION
                #undef _TJSR_PACK_DEPTH_MOTION
                #endif
                #define _TJSR_PACK_DEPTH_MOTION 0

                #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrActive.hlsl"
            ENDHLSL
        }
        
        Pass
        {
            Name "TJSR - Reconstruct"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment TjsrReconstructFragment

                #pragma multi_compile_local_fragment _ _TJSR_INTERMEDIATE_COLOR
                #pragma multi_compile_local_fragment _ _TJSR_PACK_DEPTH_MOTION

                // Enable GatherDepth4 optimization in Medium quality level.
                #ifndef UNITY_PLATFORM_WEBGL
                    #pragma target 4.5
                #endif

                #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrReconstruct.hlsl"
            ENDHLSL
        }

        //Pass
        //{
        //    Name "TJSR - Copy"

        //    HLSLPROGRAM
        //        #pragma multi_compile_local_fragment _ _ENABLE_ALPHA_OUTPUT
        //        #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrUpscale.hlsl"

        //        #pragma vertex Vert
        //        #pragma fragment TjsrCopyFrag
        //        real4 TjsrCopyFrag(Varyings input) : SV_Target
        //        {
        //            return TjsrDoCopy(input);
        //        }

        //    ENDHLSL
        //}

        Pass
        {
            Name "TJSR - Debug"

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment TjsrDebugFragment

                #pragma multi_compile_local_fragment _ _TJSR_HAS_ACTIVE_PASS
                #pragma multi_compile_local_fragment _ _TJSR_INTERMEDIATE_COLOR

                #include_with_pragmas "Packages/com.unity.render-pipelines.core/Runtime/TJSR/TjsrDebug.hlsl"
            ENDHLSL
        }
    }
}
