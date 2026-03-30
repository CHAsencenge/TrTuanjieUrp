Shader "Hidden/GDRP/VisibilityBuffer"
{
    HLSLINCLUDE

	#undef UNITY_GPU_DRIVEN_PIPELINE
	#define UNITY_GPU_DRIVEN_PIPELINE

    ENDHLSL

    SubShader
    {
        Tags{ "RenderPipeline" = "UniversalPipeline" }

        Pass
        {

			ZWrite On
			ZTest LEqual
			Blend Off
            Cull Off

			Stencil
            {
                WriteMask [_StencilWriteMaskGBufferURP]
                Ref [_StencilRefGBufferURP]
                Comp Always
                Pass Replace
            }

			HLSLPROGRAM

			#pragma target 4.5
			#pragma multi_compile_instancing
			#pragma instancing_options procedural:setup
			#pragma multi_compile _ MULTI_VIEW
			//#pragma enable_d3d11_debug_symbols
            //#pragma use_dxc metal

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "GPUDrivenCommon.hlsl"
	        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"

			struct AttributesVisibility
			{
				uint vertexID : SV_VertexID;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VaryingsVisibility
			{
				float4 positionCS : SV_POSITION;
				uint2 clusterID : TEXCOORD0;
				int4 viewPort : TEXCOORD1;
				uint4 debug : TEXCOORD2;
			};

			struct FragOut
			{
				uint visibility : SV_Target0;
			};

#if defined(PROCEDURAL_INSTANCING_ON)
			void setup()
			{

			}
#endif

			VaryingsVisibility Vert(AttributesVisibility input)
			{
				VaryingsVisibility output = (VaryingsVisibility)0;
				UNITY_SETUP_INSTANCE_ID(input);
#ifdef PROCEDURAL_INSTANCING_ON
                const uint clusterCounterIndex = GetClusterCounterIndex();
                uint clusterIndex = input.instanceID;
                uint clusterID = GetVisibleClusterID(clusterIndex, clusterCounterIndex);
                uint triangleIndex = input.vertexID / 3;

			    // Within URP, we do not support relative camera rendering.
                VertexData vertexData = GetVertexDataEx(input.vertexID, input.instanceID, false);
				output.positionCS = vertexData.clipPos;
                output.clusterID.x = vertexData.clusterID + 1;
				output.clusterID.y = vertexData.indexID;
#if MULTI_VIEW
				output.viewPort = vertexData.viewPort;
#endif
				//output.debug = vertexData.debug;

#if UNITY_UV_STARTS_AT_TOP
				output.positionCS.y = -output.positionCS.y;
#endif

#else
				output.positionCS = float4(0, 0, -1, 1);
				output.clusterID.x = 23;
				output.clusterID.y = 24;
#endif
				return output;
			}

			FragOut Frag(VaryingsVisibility input)
			{
				FragOut output = (FragOut)0;
#if MULTI_VIEW
				if (all(input.positionCS.xy >= input.viewPort.xy) && all(input.positionCS.xy <= input.viewPort.zw))
#endif
				{
					output.visibility.r = (input.clusterID.x);
					output.visibility.r |= input.clusterID.y << 25;
				}
			
#if MULTI_VIEW
				else
				{
					discard;
				}
#endif
				return output;
			}
            #pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
        }

		Pass
		{
			Name "VGShadowMapSingleView"

			ZClip [_ZClip]

            ZWrite On
            ZTest LEqual

            ColorMask 0

			HLSLPROGRAM

			#pragma target 4.5
			#pragma only_renderers d3d11 vulkan metal
			#pragma multi_compile_instancing
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
			//#pragma enable_d3d11_debug_symbols

			#pragma instancing_options procedural:setup

			#undef MULTI_VIEW

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "GPUDrivenCommon.hlsl"
	        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "GPUVisibleBucketCommon.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/VGShadowMap.hlsl"

#if defined(PROCEDURAL_INSTANCING_ON)
            void setup()
            {

            }
#endif

			#pragma vertex Vert
            #pragma fragment Frag

			ENDHLSL
		}

        Pass
        {
            Name "VGShadowMapMultiView"

			ZClip [_ZClip]

            ZWrite On
            ZTest LEqual

            ColorMask 0

			HLSLPROGRAM

			#pragma target 4.5
			#pragma only_renderers d3d11 vulkan metal
			#pragma multi_compile_instancing
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
			//#pragma enable_d3d11_debug_symbols

			#pragma instancing_options procedural:setup

			#undef MULTI_VIEW
			#define MULTI_VIEW 1

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "GPUDrivenCommon.hlsl"
	        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "GPUVisibleBucketCommon.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/Shaders/VGShadowMap.hlsl"

#if defined(PROCEDURAL_INSTANCING_ON)
            void setup()
            {

            }
#endif

			#pragma vertex Vert
            #pragma fragment Frag

			ENDHLSL
        }

        Pass
        {
			Name "VGPicking"

			//ZWrite On ZTest LEqual Blend Off
            Cull back

			HLSLPROGRAM

			#pragma target 4.5
			#pragma only_renderers d3d11 vulkan metal
			#pragma multi_compile_instancing
			#pragma instancing_options procedural:setup
			//#pragma enable_d3d11_debug_symbols
            //#pragma use_dxc metal
			#pragma shader_feature UNITY_EDITOR

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "GPUDrivenCommon.hlsl"
	        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"

			struct AttributesPicking
			{
				uint vertexID : SV_VertexID;
				DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct VaryingsPicking
			{
				float4 positionCS : SV_POSITION;
				float4 payload : TEXCOORD0;
			};

#if defined(PROCEDURAL_INSTANCING_ON)
			void setup()
			{

			}
#endif
			struct PickingId
			{
				float4 packedId;
			};
			StructuredBuffer<PickingId> _PickingPayloadBuffer;
#if UNITY_EDITOR
            ByteAddressBuffer _InstanceHeaderEditorBuffer;
#endif

			VaryingsPicking Vert(AttributesPicking input)
			{
				VaryingsPicking output = (VaryingsPicking)0;
				UNITY_SETUP_INSTANCE_ID(input);
#ifdef PROCEDURAL_INSTANCING_ON
                const uint clusterCounterIndex = GetClusterCounterIndex();
                uint clusterIndex = input.instanceID;
                uint clusterID = GetVisibleClusterID(clusterIndex, clusterCounterIndex);
                uint triangleIndex = input.vertexID / 3;
			    // Within URP, we do not support relative camera rendering.
                VertexData vertexData = GetVertexDataEx(input.vertexID, input.instanceID, false);
				//output.positionCS = mul(UNITY_MATRIX_VP, vertexData.worldPos);
				output.positionCS = vertexData.clipPos;

#if UNITY_UV_STARTS_AT_TOP
				output.positionCS.y = -output.positionCS.y;
#endif
				SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
#if UNITY_EDITOR
    			uint payloadIndex = GDRP_ACCESS_PROP(InstanceHeaderEditor, uint, payloadIndex, survivalCluster.instanceId);
				output.payload = _PickingPayloadBuffer[payloadIndex].packedId;
#endif
#else
				output.positionCS = float4(0, 0, -1, 1);
#endif
				return output;
			}

			void Frag(VaryingsPicking input, out float4 outColor : SV_Target0)
			{
				outColor = input.payload;
			}

			
            #pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
        }

		Pass
        {
			Name "VBuffer"

			ZWrite On
			ZTest LEqual
			Blend Off
            Cull back

			Stencil
            {
                WriteMask [_StencilWriteMaskGBufferURP]
                Ref [_StencilRefGBufferURP]
                Comp Always
                Pass Replace
            }

			HLSLPROGRAM
			#pragma target 4.5
			#pragma only_renderers d3d11 vulkan metal
			#pragma multi_compile_instancing
			#pragma instancing_options procedural:setup
			#pragma multi_compile _ MULTI_VIEW
			//#pragma enable_d3d11_debug_symbols
            //#pragma use_dxc metal

			#include_with_pragmas "GPUDataDecodeDefine.hlsl"
			#include "GPUDrivenCommon.hlsl"
	        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInputGDRP.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityInput.hlsl"
	        #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
			#include "GPUVisibleBucketCommon.hlsl"

			struct AttributesVisibility
			{
				uint vertexID : SV_VertexID;
				DEFAULT_UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct FragOut
			{
				uint visibility : SV_Target0;
			};

#if defined(PROCEDURAL_INSTANCING_ON)
			void setup()
			{

			}
#endif			

			VaryingsBinning Vert(AttributesVisibility input)
			{
				VaryingsBinning output = (VaryingsBinning)0;
				UNITY_SETUP_INSTANCE_ID(input);
#ifdef PROCEDURAL_INSTANCING_ON
                output = GetVaryingsBinningData(input.instanceID, input.vertexID);

#else
				output.positionCS = float4(0, 0, -1, 1);
                output.visibility.x = 23;
                output.visibility.x |= 24 << 25;
#endif
				return output;
			}

			FragOut Frag(VaryingsBinning input)
			{
				FragOut output = (FragOut)0;
#if MULTI_VIEW
				if (all(input.positionCS.xy >= input.viewPort.xy) && all(input.positionCS.xy <= input.viewPort.zw))
#endif
				{
					output.visibility.r = input.visibility.x;
				}
#if MULTI_VIEW
				else
				{
					discard;
				}
#endif
				return output;
			}

			#pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
    	}
	}
    Fallback Off
}
