Shader "Hidden/HDRP/MaterialError"
{
    SubShader
    {
            Pass
            {
                Name "DebugMaterialID"

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
                float _MaxRange;

                v2f vert(appdata_t v)
                {
                    v2f o;
                    o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                    return o;
                }

                float4 frag(v2f i) : SV_Target
                {
                    uint2 uv = i.positionCS.xy;
                    float4 color = float4(0.0f, 0.0f, 0.0f, 1.0f);
                    uint visibilityPixel = LOAD_TEXTURE2D(_VisibilityBuffer, uv).r;
                    uint clusterID = GetVisibleClusterID(visibilityPixel);
                    if (clusterID != ~0u)
                    {
                        uint triangleID = GetTriangleID(visibilityPixel);
                        uint materialID = GetMaterialID(clusterID, triangleID);
                        materialID &= 0x3FFF;
                        uint index = materialID % (DEBUG_COLORS_COUNT - 1) + 1;
                        color = kDebugColorGradient[index];
                    }
                    return color;
                }
                ENDHLSL
            }

            Pass
            {
                Name "DebugMaterialRange"

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
                #include "GPUDrivenCommon.hlsl"

                struct appdata_t
                {
                    uint vertexID : SV_VertexID;
                };

                struct v2f
                {
                    float4 positionCS : SV_POSITION;
                };

                StructuredBuffer<uint4> _MaterialRangeBuffer;
                uniform uint2 _Viewport;
                uniform uint2 _TileSize;

                v2f vert(appdata_t v)
                {
                    v2f o;
                    o.positionCS = GetFullScreenTriangleVertexPosition(v.vertexID);
                    return o;
                }

                float4 frag(v2f i) : SV_Target
                {
                    uint2 uv = i.positionCS.xy;
                    uint2 xy = uv * _Viewport;
                    xy = uv / 64;
                    uint id = (xy.y) * _TileSize.x + xy.x;
                    uint4 range = _MaterialRangeBuffer[id];
                    const float max = 2097152.0f / 1000.0f;
                    float4 color;
                    color.r = ((range.x >> 22) | (range.y >> 21 << 10)) / max;
                    color.g = (((range.x << 10 >> 22)) | (range.y << 11 >> 21 << 10)) / max;
                    color.b = ((range.x << 20 >> 20) | (range.y << 22 >> 10)) / max;
                    color.a = 1.0f;
                    return color;
                }
                ENDHLSL
            }
    }
    Fallback Off
}
