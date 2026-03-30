// Custom Deferred Lighting Shader
// Full-screen pass that reads the custom GBuffer, reconstructs world position from depth,
// and evaluates all light contributions using the shading model dispatch system.
// Architecture referenced from UE5 DeferredLightPixelShaders.usf.
Shader "Hidden/Custom/DeferredLighting"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "CustomDeferredLighting"

            ZWrite Off
            ZTest Always
            Cull Off

            // Only write to pixels marked by the GBuffer pass (stencil bit 6)
            Stencil
            {
                Ref 64
                ReadMask 64
                Comp Equal
            }

            // Replace (not additive): deferred lighting result is the final lit color
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex DeferredLightingVert
            #pragma fragment DeferredLightingFrag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT

            #include "Packages/com.tr.render/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.tr.render/Shaders/CustomDeferredLight.hlsl"

            // GBuffer textures bound by the C# pass
            TEXTURE2D(_CustomGBuffer0); SAMPLER(sampler_CustomGBuffer0);
            TEXTURE2D(_CustomGBuffer1); SAMPLER(sampler_CustomGBuffer1);
            TEXTURE2D(_CustomGBuffer2); SAMPLER(sampler_CustomGBuffer2);
            TEXTURE2D(_CustomGBuffer3); SAMPLER(sampler_CustomGBuffer3);
            TEXTURE2D(_CustomGBuffer4); SAMPLER(sampler_CustomGBuffer4);

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord   : TEXCOORD0;
            };

            // Full-screen triangle vertex shader (3 vertices, no vertex buffer needed)
            Varyings DeferredLightingVert(Attributes input)
            {
                Varyings output;

                // Generate full-screen triangle from vertex ID
                // Vertex 0: (-1, -1), Vertex 1: (3, -1), Vertex 2: (-1, 3)
                float2 uv = float2((input.vertexID << 1) & 2, input.vertexID & 2);
                output.positionCS = float4(uv * 2.0 - 1.0, UNITY_NEAR_CLIP_VALUE, 1.0);
                output.texcoord = uv;

                // Handle Y flip for platforms where UV origin is at the top
                #if UNITY_UV_STARTS_AT_TOP
                    output.texcoord.y = 1.0 - output.texcoord.y;
                #endif

                return output;
            }

            half4 DeferredLightingFrag(Varyings input) : SV_Target
            {
                float2 screenUV = input.texcoord;

                // Sample depth using URP's declared depth texture utility
                float rawDepth = SampleSceneDepth(screenUV);

                #if UNITY_REVERSED_Z
                    bool isSky = rawDepth == 0.0;
                #else
                    bool isSky = rawDepth == 1.0;
                #endif

                if (isSky)
                    return half4(0.0, 0.0, 0.0, 0.0);

                // Sample all GBuffer targets
                half4 gb0 = SAMPLE_TEXTURE2D(_CustomGBuffer0, sampler_CustomGBuffer0, screenUV);
                half4 gb1 = SAMPLE_TEXTURE2D(_CustomGBuffer1, sampler_CustomGBuffer1, screenUV);
                half4 gb2 = SAMPLE_TEXTURE2D(_CustomGBuffer2, sampler_CustomGBuffer2, screenUV);
                half3 gb3 = SAMPLE_TEXTURE2D(_CustomGBuffer3, sampler_CustomGBuffer3, screenUV).rgb;
                half4 gb4 = SAMPLE_TEXTURE2D(_CustomGBuffer4, sampler_CustomGBuffer4, screenUV);

                // Decode GBuffer
                CustomGBufferData gbufferData = DecodeGBuffer(gb0, gb1, gb2, gb3, gb4);

                // Reconstruct world position from depth
                float3 positionWS = ReconstructWorldPosition(screenUV, rawDepth);

                // Compute view direction
                half3 viewDirWS = half3(normalize(GetWorldSpaceViewDir(positionWS)));

                // Compute full deferred lighting
                half3 finalColor = ComputeDeferredLighting(gbufferData, positionWS, viewDirWS);

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }

    FallBack Off
}
