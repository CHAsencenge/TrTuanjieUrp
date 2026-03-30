Shader "Hidden/GDRP/DecalBufferEmit"
{
    HLSLINCLUDE

    //#pragma enable_d3d11_debug_symbols
    #undef UNITY_GPU_DRIVEN_PIPELINE
    #define UNITY_GPU_DRIVEN_PIPELINE
    #include_with_pragmas "GPUDataDecodeDefine.hlsl"
    #include "GPUDrivenCommon.hlsl"
    #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/Shaders/VGUtilities.hlsl"

    ENDHLSL

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "DBuffer Emit"

			ZWrite Off
			ZTest  LEqual
			Blend  Off
            Cull   Off

            HLSLPROGRAM

            #pragma target 4.5
            #pragma editor_sync_compilation
            #pragma only_renderers d3d11 vulkan metal
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 texcoord  : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }
            
            void Frag(Varyings input,
                out float4 outRenderingLayers : SV_Target)
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                uint2 uv = input.positionCS.xy;
                uint pixelValue = LOAD_TEXTURE2D(_VisibilityBuffer, uv).r;
                uint clusterID = GetVisibleClusterID(pixelValue);
                if (clusterID == ~0u) discard;

                // We only use instance here, so we can use GetFragDataEX or get instance by self.
                SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
                InstanceSubset instance = _InstanceSubsetBuffer[survivalCluster.instanceId];

                uint renderingLayers = asuint(instance.renderingLayerMask);
                outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
            }

            ENDHLSL
        }
    }
}
