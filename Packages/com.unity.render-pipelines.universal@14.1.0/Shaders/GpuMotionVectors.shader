Shader "Hidden/Universal Render Pipeline/GpuMotionVectors"
{
    SubShader
    {
        Pass
        {
            Name "Gpu Driven Motion Vectors"

            Tags{ "LightMode" = "GpuMotionVectors" }

            HLSLPROGRAM
            #pragma multi_compile_fragment _ _FOVEATED_RENDERING_NON_UNIFORM_RASTER
            #pragma never_use_dxc metal

            #pragma exclude_renderers d3d11_9x
            #pragma target 3.5

            #pragma vertex Vert
            #pragma fragment Frag

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #ifndef HAVE_VFX_MODIFICATION
                #pragma multi_compile _ DOTS_INSTANCING_ON
                #if UNITY_PLATFORM_ANDROID || UNITY_PLATFORM_WEBGL || UNITY_PLATFORM_UWP
                    #pragma target 3.5 DOTS_INSTANCING_ON
                #else
                    #pragma target 4.5 DOTS_INSTANCING_ON
                 #endif
            #endif 

            // -------------------------------------
            // Includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
            #include_with_pragmas "GPUDataDecodeDefine.hlsl"

            // HAVE_VFX_MODIFICATION
            #if defined(_FOVEATED_RENDERING_NON_UNIFORM_RASTER)
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/FoveatedRendering.hlsl"
            #endif

            #include "Packages/com.unity.render-pipelines.universal/Shaders/GpuMotionVectors.hlsl"

            ENDHLSL
        }
    }
}
