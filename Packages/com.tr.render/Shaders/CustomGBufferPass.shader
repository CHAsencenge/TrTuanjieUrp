// Custom Deferred GBuffer Pass Shader
// Renders opaque surfaces into the custom GBuffer layout.
// Uses LightMode "CustomDeferredGBuffer" so URP's forward pass ignores these objects.
Shader "Custom/DeferredGBuffer"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        _Metallic("Metallic", Range(0, 1)) = 0.0
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        _Specular("Specular", Range(0, 1)) = 0.5
        _OcclusionStrength("Occlusion Strength", Range(0, 1)) = 1.0
        _BumpScale("Normal Scale", Float) = 1.0
        [HDR] _EmissionColor("Emission Color", Color) = (0, 0, 0, 0)

        [NoScaleOffset] _BumpMap("Normal Map", 2D) = "bump" {}
        [NoScaleOffset] _MetallicGlossMap("Metallic Map", 2D) = "white" {}
        [NoScaleOffset] _OcclusionMap("Occlusion Map", 2D) = "white" {}
        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
        [HideInInspector] _ShadingModelId("Shading Model", Float) = 0
        [HideInInspector] _MaterialFlags("Material Flags", Float) = 0
        _CustomData("Custom Data", Vector) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        // GBuffer write pass
        Pass
        {
            Name "CustomDeferredGBuffer"
            Tags { "LightMode" = "CustomDeferredGBuffer" }

            ZWrite On
            ZTest LEqual
            Cull Back

            // Mark deferred pixels in stencil so the lighting pass only affects them
            Stencil
            {
                Ref 64
                WriteMask 64
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex GBufferVert
            #pragma fragment GBufferFrag

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _METALLICGLOSSMAP
            #pragma shader_feature_local _OCCLUSIONMAP
            #pragma shader_feature_local _EMISSION

            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma multi_compile_instancing

            #include "Packages/com.tr.render/Shaders/CustomDeferredLitInput.hlsl"
            #include "Packages/com.tr.render/Shaders/CustomGBuffer.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 texcoord   : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float4 tangentWS   : TEXCOORD2;
                float3 positionWS  : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings GBufferVert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.normalWS = normalInput.normalWS;

                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = half4(normalInput.tangentWS.xyz, sign);

                return output;
            }

            // MRT output: 5 render targets for PC layout
            struct GBufferOutput
            {
                half4 gbuffer0 : SV_Target0;
                half4 gbuffer1 : SV_Target1;
                half4 gbuffer2 : SV_Target2;
                half4 gbuffer3 : SV_Target3; // B10G11R11 accepts half4, GPU ignores .a
                half4 gbuffer4 : SV_Target4;
            };

            GBufferOutput GBufferFrag(Varyings input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Sample surface data from textures and material properties
                CustomSurfaceData surface = InitializeSurfaceData(input.uv, input.normalWS, input.tangentWS);

                // Build GBuffer data
                CustomGBufferData gbufferData = (CustomGBufferData)0;
                gbufferData.baseColor      = surface.baseColor;
                gbufferData.normalWS       = surface.normalWS;
                gbufferData.metallic       = surface.metallic;
                gbufferData.smoothness     = surface.smoothness;
                gbufferData.specular       = surface.specular;
                gbufferData.ao             = surface.ao;
                gbufferData.emissive       = surface.emissive;
                gbufferData.shadingModelId = surface.shadingModelId;
                gbufferData.materialFlags  = surface.materialFlags;
                gbufferData.customData     = surface.customData;

                // Encode to GBuffer
                half4 gb0, gb1, gb2, gb4;
                half3 gb3;
                EncodeGBuffer(gbufferData, gb0, gb1, gb2, gb3, gb4);

                GBufferOutput output;
                output.gbuffer0 = gb0;
                output.gbuffer1 = gb1;
                output.gbuffer2 = gb2;
                output.gbuffer3 = half4(gb3, 1.0);
                output.gbuffer4 = gb4;

                return output;
            }

            ENDHLSL
        }

        // Depth-only pass for shadow casting
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma multi_compile_instancing

            #include "Packages/com.tr.render/Shaders/CustomDeferredLitInput.hlsl"
            #include "Packages/com.tr.render/ShaderPasses/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // Depth-only pass for depth prepass
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #pragma multi_compile_instancing

            #include "Packages/com.tr.render/Shaders/CustomDeferredLitInput.hlsl"
            #include "Packages/com.tr.render/ShaderPasses/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
