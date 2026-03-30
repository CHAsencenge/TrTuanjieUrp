#if SHADERPASS != SHADERPASS_CUSTOM_UI
#error SHADERPASS_CUSTOM_UI_is_not_correctly_defined
#endif

#include "CanvasVertexTransforms.hlsl"

// Constants for UI clip rect optimization
#define UI_CLIP_RECT_CLAMP_RANGE 1e6
#define UI_SOFTNESS_SCALE_FACTOR 0.25
#define ALPHA_PRECISION 255.0h

// Helper function to calculate UI clip rect data
float4 CalculateUIClipRectData(float3 positionOS, float4 clipRect, float2 maskSoftness)
{
    // Clamp clip rectangle to prevent overflow
    float4 clampedClipRect = clamp(clipRect, -UI_CLIP_RECT_CLAMP_RANGE, UI_CLIP_RECT_CLAMP_RANGE);
    
    // Pre-calculate clip rect center and half-size for better performance
    float2 clipRectCenter = (clampedClipRect.xy + clampedClipRect.zw) * 0.5;
    float2 clipRectHalfSize = (clampedClipRect.zw - clampedClipRect.xy) * 0.5;
    
    // Calculate screen scale for softness calculation
    float2 screenScale = abs(mul((float2x2)UNITY_MATRIX_P, _ScreenParams.xy));
    
    // Store optimized clip mask data
    // xy: distance from center to edges, zw: softness factors
    return float4(
        positionOS.xy - clipRectCenter,
        UI_SOFTNESS_SCALE_FACTOR / (UI_SOFTNESS_SCALE_FACTOR * maskSoftness + screenScale)
    );
}

// Helper function to apply UI clip rect in fragment shader
half ApplyUIClipRect(float4 clipRectData, float4 clipRect)
{
    // Optimized clip mask calculation using pre-computed center-based distances
    half2 clipRectHalfSize = (clipRect.zw - clipRect.xy) * 0.5;
    half2 distanceFromCenter = abs(clipRectData.xy);
    half2 softnessFactors = clipRectData.zw;
    
    // Calculate clip mask with improved precision
    half2 uiClipMask = saturate((clipRectHalfSize - distanceFromCenter) * softnessFactors);
    return uiClipMask.x * uiClipMask.y;
}

// Helper function to handle position transformation - fixed logic error
void TransformPosition(float3 positionOS, out float3 positionWS, out float4 positionCS)
{
    // Always use consistent transformation regardless of UV system
    positionWS = TransformObjectToWorld(positionOS);
    positionCS = TransformObjectToHClip(positionOS);
}

// Construct the output variables for the vertex shader
Varyings BuildCanvasVaryings(Attributes input)
{
    Varyings output;
    ZERO_INITIALIZE(Varyings, output);

    // Set instance ID and stereo rendering
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    // Transform position with platform-specific handling
    float3 positionWS;
    float4 positionCS;
    TransformPosition(input.positionOS, positionWS, positionCS);
    output.positionCS = positionCS;

    // Set texture coordinates with platform-specific UV handling
    #if defined(VARYINGS_NEED_TEXCOORD0) || defined(VARYINGS_DS_NEED_TEXCOORD0)
        output.texCoord0 = input.uv0;
    #endif

    // Initialize variables only when needed
    #ifdef ATTRIBUTES_NEED_NORMAL
        float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
    #else
        float3 normalWS = float3(0.0, 0.0, 0.0);
    #endif

    #ifdef ATTRIBUTES_NEED_TANGENT
        float4 tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), input.tangentOS.w);
    #endif

    // Apply vertex modification in camera-relative space (if enabled)
    #if defined(HAVE_VERTEX_MODIFICATION)
        ApplyVertexModification(input, normalWS, positionWS, _TimeParameters.xyz);
    #endif

    // Set various output variables
    #ifdef VARYINGS_NEED_POSITION_WS
        output.positionWS = positionWS;
    #endif

    #ifdef VARYINGS_NEED_NORMAL_WS
        output.normalWS = normalWS;
    #endif

    #ifdef VARYINGS_NEED_TANGENT_WS
        output.tangentWS = tangentWS;
    #endif

    // UI mask handling
    #if defined(VARYINGS_NEED_TEXCOORD1) || defined(VARYINGS_DS_NEED_TEXCOORD1)
        #ifdef UNITY_UI_CLIP_RECT
            output.texCoord1 = CalculateUIClipRectData(input.positionOS, _ClipRect, half2(_UIMaskSoftnessX, _UIMaskSoftnessY));
        #endif
    #endif

    // Set additional texture coordinates
    #if defined(VARYINGS_NEED_TEXCOORD2) || defined(VARYINGS_DS_NEED_TEXCOORD2)
        output.texCoord2 = input.uv2;
    #endif

    #if defined(VARYINGS_NEED_TEXCOORD3) || defined(VARYINGS_DS_NEED_TEXCOORD3)
        output.texCoord3 = input.uv3;
    #endif

    // Set vertex color
    #if defined(VARYINGS_NEED_COLOR) || defined(VARYINGS_DS_NEED_COLOR)
        output.color = input.color;
    #endif

    // Set screen position
    #ifdef VARYINGS_NEED_SCREENPOSITION
        output.screenPosition = ClipToNDC(output.positionCS);
    #endif

    return output;
}

// Vertex shader main function
PackedVaryings vert(Attributes input)
{
    return PackVaryings(BuildCanvasVaryings(input));
}

// Fragment shader main function
half4 frag(PackedVaryings packedInput) : SV_TARGET
{
    // Unpack input variables
    Varyings unpacked = UnpackVaryings(packedInput);
    UNITY_SETUP_INSTANCE_ID(unpacked);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(unpacked);
    
    // Compute surface description
    SurfaceDescriptionInputs surfaceDescriptionInputs = BuildSurfaceDescriptionInputs(unpacked);
    SurfaceDescription surfaceDescription = SurfaceDescriptionFunction(surfaceDescriptionInputs);

    // Alpha precision handling to avoid instability
    const half invAlphaPrecision = 1.0h / ALPHA_PRECISION;
    unpacked.color.a = round(unpacked.color.a * ALPHA_PRECISION) * invAlphaPrecision;

    // Compute final color
    half alpha = surfaceDescription.Alpha;
    half4 color = half4(surfaceDescription.BaseColor + surfaceDescription.Emission, alpha);

    // Apply color adjustment
    #if !defined(HAVE_VFX_MODIFICATION) && !defined(UNITY_UI_DISABLE_COLOR_TINT)
        color *= unpacked.color;
    #endif

    // Apply UI clip rect
    #ifdef UNITY_UI_CLIP_RECT
        color.a *= ApplyUIClipRect(unpacked.texCoord1, _ClipRect);
    #endif

    // Alpha test
    #if _ALPHATEST_ON
        clip(alpha - surfaceDescription.AlphaClipThreshold);
    #endif

    // Premultiply alpha
    color.rgb *= color.a;

    return color;
}
