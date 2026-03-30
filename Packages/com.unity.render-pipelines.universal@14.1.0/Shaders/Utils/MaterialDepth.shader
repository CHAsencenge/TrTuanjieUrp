Shader "Hidden/GDRP/MaterialDepth"
{
    HLSLINCLUDE
		
    ENDHLSL

    SubShader
    {
        Tags{ "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
			Cull Back
			ZWrite On
			ZTest Off 
		

			HLSLPROGRAM

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
			#include "GPUDrivenCommon.hlsl"

			//#pragma target 4.5
			//#pragma use_dxc metal
			#pragma only_renderers d3d11 vulkan metal
			//#pragma enable_d3d11_debug_symbols

			Texture2D<uint4> _VisibilityBuffer;

			struct Attributes
			{
				uint vertexID : SV_VertexID;
				DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct Varyings
			{
				float4 positionCS : SV_POSITION;
				DEFAULT_UNITY_VERTEX_OUTPUT_STEREO
			};

			struct FragOut
			{
				float materialID : SV_Depth;
			};


			Varyings Vert(Attributes input)
			{
				Varyings output;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
				output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
				return output;
			}

			void Frag(Varyings input, out float materialDepth : SV_Depth)
			{
				uint2 uv = input.positionCS.xy;
                uint pixel = LOAD_TEXTURE2D(_VisibilityBuffer, uv).r;
                uint clusterID = GetVisibleClusterID(pixel);
                uint triangleID = GetTriangleID(pixel);
				
                uint materialID = GetMaterialID(clusterID, triangleID);
				materialDepth = asfloat(materialID);
			}

			
            #pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
        }
    }
    Fallback Off
}
