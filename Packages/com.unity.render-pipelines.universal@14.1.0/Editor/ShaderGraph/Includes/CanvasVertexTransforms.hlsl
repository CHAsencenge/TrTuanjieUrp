// CanvasVertexTransforms.hlsl
// Vertex transformation utilities for Canvas shaders

// Constants for transformation calculations
#define NDC_SCALE_FACTOR 0.5f
#define HOMOGENEOUS_W 1.0f

// Combine model-to-world and world-to-clip transformations in a single matrix multiplication
// Optimized for Canvas UI rendering with minimal overhead
float4 TransformModelToHClip(float3 positionOS)
{
    float4 positionWS = float4(positionOS, HOMOGENEOUS_W);
    float4 positionCS = mul(UNITY_MATRIX_VP, mul(UNITY_MATRIX_M, positionWS));
    return positionCS;
}

// Transforms a position from clip space to normalized device coordinates (NDC).
// Handles projection Y flip for platform compatibility (DirectX vs OpenGL).
// Optimized for Canvas UI rendering with minimal calculations.
float4 ClipToNDC(float3 positionCS)
{
    float4 positionNDC;
    positionNDC.xy = positionCS.xy * NDC_SCALE_FACTOR;
    positionNDC.y *= _ProjectionParams.x;  // Unity flips Y for some platforms
    positionNDC.z = positionCS.z;          // Maintain depth
    positionNDC.w = HOMOGENEOUS_W;         // Homogeneous coordinate
    return positionNDC;
} 

