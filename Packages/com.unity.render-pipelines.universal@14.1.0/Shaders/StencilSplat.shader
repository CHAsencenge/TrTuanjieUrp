Shader "Hidden/Universal Render Pipeline/StencilSplat"
{
    Properties {
        _StencilRef ("StencilRef", Int) = 0
        _StencilReadMask ("StencilReadMask", Int) = 0
        _StencilWriteMask ("StencilWriteMask", Int) = 0
    }

    // HLSLINCLUDE
    // #pragma enable_d3d11_debug_symbols
    // ENDHLSL

    HLSLINCLUDE
    // Includes
    #include_with_pragmas "GPUDataDecodeDefine.hlsl"
    #include "GPUDrivenCommon.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"

    struct Attributes
    {
        uint vertexID     : SV_VertexID;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float2 texcoord   : TEXCOORD0;
        UNITY_VERTEX_OUTPUT_STEREO
    };

    // -------------------------------------
    // Vertex
    Varyings Vert(Attributes input)
    {
        Varyings output;
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
        output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
        output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
        return output;
    }

    // -------------------------------------
    // Fragment
    TEXTURE2D_X_HALF(_GBuffer0);
    SamplerState my_point_clamp_sampler;

    void Frag(Varyings input)
    {
        half4 gbuffer0 = SAMPLE_TEXTURE2D_X_LOD(_GBuffer0, my_point_clamp_sampler, input.texcoord, 0);

        if (gbuffer0.a == 1.0)  // do not update stencil if gbuffer0 is not filled in GbufferSplatPass
            discard;

        uint materialFlags = UnpackMaterialFlags(gbuffer0.a);

        if ((materialFlags & kMaterialFlagSimpleLit) == 0)
            discard;
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Gpu Driven Stencil Splat"

            Tags{ "LightMode" = "StencilSplat" }
            ZWrite Off
			ZTest Off
			Blend Off
            Cull Off
            ColorMask 0

            Stencil
            {
                WriteMask [_StencilWriteMask]
                Ref [_StencilRef]
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma never_use_dxc metal

            #pragma exclude_renderers d3d11_9x
            #pragma target 4.5

            #pragma vertex Vert
            #pragma fragment Frag

            ENDHLSL
        }
    }
}
