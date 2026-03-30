Shader "Hidden/HDRP/DebugVisibility"
{
    SubShader
    {
        Pass
        {
            Name "DebugClusterID"

            ZTest Off
            ZWrite Off

            HLSLPROGRAM

            #pragma only_renderers d3d11 vulkan metal
            //#pragma enable_d3d11_debug_symbols
            #pragma vertex vert
            #pragma fragment frag

            #include_with_pragmas "GPUDataDecodeDefine.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Debug.hlsl"
            //#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
            #include "GPUDrivenCommon.hlsl"

            struct appdata_t
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };


            Texture2D<uint4> _VisibilityBuffer;
            v2f vert (appdata_t v)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                uint2 uv = i.positionCS.xy;
                uint clusterID = GetVisibleClusterID(LOAD_TEXTURE2D(_VisibilityBuffer, uv).r);
                if (clusterID == ~0u)
                    return float4(0, 0, 0, 1);

                SurvivalCluster SurvivalCluster = LoadSurvivalCluster(clusterID);
                clusterID = SurvivalCluster.clusterIndex;
                uint index = clusterID % (DEBUG_COLORS_COUNT - 1) + 1;
                float4 color = kDebugColorGradient[index];
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DebugTriangleID"

            ZTest Off
            ZWrite Off

            HLSLPROGRAM

            #pragma only_renderers d3d11 vulkan metal
            //#pragma enable_d3d11_debug_symbols
            #pragma vertex vert
            #pragma fragment frag

            #include_with_pragmas "GPUDataDecodeDefine.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Debug.hlsl"
            //#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
            #include "GPUDrivenCommon.hlsl"

            struct appdata_t
            {
                uint vertexID : SV_VertexID;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            Texture2D<uint4> _VisibilityBuffer;

            v2f vert(appdata_t v)
            {
                v2f o;
                o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                uint2 uv = i.positionCS.xy;
                uint pixel = (LOAD_TEXTURE2D(_VisibilityBuffer, uv).r);
                uint clusterID = GetVisibleClusterID(pixel);
                if (clusterID == ~0u)
                    return float4(0, 0, 0, 1);

                SurvivalCluster SurvivalCluster = LoadSurvivalCluster(clusterID);
                clusterID = SurvivalCluster.clusterIndex;
                uint triangleID = GetTriangleID(pixel);
                uint index = (clusterID + triangleID) % (DEBUG_COLORS_COUNT - 1) + 1;

                float4 color = kDebugColorGradient[index];
                color.rgb = color.x * 0.299f + color.y * 0.587f + color.z * 0.114f;
                return color;
            }
            ENDHLSL
        }

            Pass
            {
                Name "DebugInstanceID"

                ZTest Off
                ZWrite Off

                HLSLPROGRAM

                #pragma only_renderers d3d11 vulkan metal
                //#pragma enable_d3d11_debug_symbols
                #pragma vertex vert
                #pragma fragment frag

                #include_with_pragmas "GPUDataDecodeDefine.hlsl"
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
                //#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Debug.hlsl"
                #include "GPUDrivenCommon.hlsl"

                struct appdata_t
                {
                    uint vertexID : SV_VertexID;
                };

                struct v2f
                {
                    float4 positionCS : SV_POSITION;
                };


                Texture2D<uint4> _VisibilityBuffer;
                v2f vert(appdata_t v)
                {
                    v2f o;
                    o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                    return o;
                }

                real4 frag(v2f i) : SV_Target
                {
                    uint2 uv = i.positionCS.xy;
                    uint clusterID = GetVisibleClusterID(LOAD_TEXTURE2D(_VisibilityBuffer, uv).r);
                    if (clusterID == ~0u)
                        return float4(0, 0, 0, 1);

                    SurvivalCluster SurvivalCluster = LoadSurvivalCluster(clusterID);
                    uint instanceID = SurvivalCluster.instanceId;
                    uint index = instanceID % (DEBUG_COLORS_COUNT - 1) + 1;
                    float4 color = kDebugColorGradient[index];
                    return color;
                }
                ENDHLSL
            }

            Pass
            {
                Name "DebugClusterHLOD"

                ZTest Off
                ZWrite Off

                HLSLPROGRAM

                #pragma only_renderers d3d11 vulkan metal
                //#pragma enable_d3d11_debug_symbols
                #pragma vertex vert
                #pragma fragment frag

                #include_with_pragmas "GPUDataDecodeDefine.hlsl"
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
                #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Debug.hlsl"
                //#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
                #include "GPUDrivenCommon.hlsl"

                struct appdata_t
                {
                    uint vertexID : SV_VertexID;
                };

                struct v2f
                {
                    float4 positionCS : SV_POSITION;
                };


                Texture2D<uint4> _VisibilityBuffer;
                v2f vert(appdata_t v)
                {
                    v2f o;
                    o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                    return o;
                }

                float4 frag(v2f i) : SV_Target
                {
                    uint2 uv = i.positionCS.xy;
                    uint clusterID = GetVisibleClusterID(LOAD_TEXTURE2D(_VisibilityBuffer, uv).r);
                    if (clusterID == ~0u)
                        return float4(0, 0, 0, 1);

                    SurvivalCluster SurvivalCluster = LoadSurvivalCluster(clusterID);
                    uint lod = (SurvivalCluster.clusterFlag >> 3) & 0xF;
                    uint index = lod % 15;
                    real3 color = GetIndexColor(index);
                    return real4(color, 1.0f);
                }
                ENDHLSL
            }

    }
    Fallback Off
}
