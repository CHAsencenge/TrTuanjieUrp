#ifndef UNIVERSAL_MOTION_VECTORS_PASS_INCLUDED
#define UNIVERSAL_MOTION_VECTORS_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MotionVectorsCommon.hlsl"

struct MotionVectorPassAttributes
{
    float3 prevPosOS  : TEXCOORD4; // Contains previous frame local vertex position (for skinned meshes)
};

// Note: these will have z == 0.0f in the pixel shader to save on bandwidth
struct MotionVectorPassVaryings
{
    float4 posCSNoJitter;
    float4 prevPosCSNoJitter;
};

struct PackedMotionVectorPassVaryings
{
    float3 posCSNoJitter         : CLIP_POSITION_NO_JITTER;
    float3 prevPosCSNoJitter : PREVIOUS_CLIP_POSITION_NO_JITTER;
};

PackedMotionVectorPassVaryings PackMotionVectorVaryings(MotionVectorPassVaryings regularVaryings)
{
    PackedMotionVectorPassVaryings packedVaryings;
    packedVaryings.posCSNoJitter = regularVaryings.posCSNoJitter.xyw;
    packedVaryings.prevPosCSNoJitter = regularVaryings.prevPosCSNoJitter.xyw;
    return packedVaryings;
}

MotionVectorPassVaryings UnpackMotionVectorVaryings(PackedMotionVectorPassVaryings packedVaryings)
{
    MotionVectorPassVaryings regularVaryings;
    regularVaryings.posCSNoJitter = float4(packedVaryings.posCSNoJitter.xy, 0, packedVaryings.posCSNoJitter.z);
    regularVaryings.prevPosCSNoJitter = float4(packedVaryings.prevPosCSNoJitter.xy, 0, packedVaryings.prevPosCSNoJitter.z);
    return regularVaryings;
}

float3 GetLastFrameDeformedPosition(Attributes input, MotionVectorPassOutput currentFrameMvData, float3 prevPosOS)
{
    Attributes lastFrameInputAttributes = input;
    lastFrameInputAttributes.positionOS = prevPosOS;

    VertexDescriptionInputs lastFrameVertexDescriptionInputs = BuildVertexDescriptionInputs(lastFrameInputAttributes);
#if defined(AUTOMATIC_TIME_BASED_MOTION_VECTORS) && defined(GRAPH_VERTEX_USES_TIME_PARAMETERS_INPUT)
    lastFrameVertexDescriptionInputs.TimeParameters = _LastTimeParameters.xyz;
#endif

    VertexDescription lastFrameVertexDescription = VertexDescriptionFunction(lastFrameVertexDescriptionInputs
#if defined(HAVE_VFX_MODIFICATION)
        , currentFrameMvData.vfxGraphProperties
#endif
    );

#if defined(HAVE_VFX_MODIFICATION)
    lastFrameInputAttributes.positionOS = lastFrameVertexDescription.Position.xyz;
    lastFrameInputAttributes = VFXTransformMeshToPreviousElement(lastFrameInputAttributes, currentFrameMvData.vfxElementAttributes);
    prevPosOS = lastFrameInputAttributes.positionOS;
#else
    prevPosOS = lastFrameVertexDescription.Position.xyz;
#endif
    return prevPosOS;
}

void vert(
    Attributes input,
    MotionVectorPassAttributes passInput,
    out PackedMotionVectorPassVaryings packedMvOutput,
    out PackedVaryings packedOutput)
{
    Varyings output = (Varyings)0;
    MotionVectorPassVaryings mvOutput = (MotionVectorPassVaryings)0;
    MotionVectorPassOutput currentFrameMvData = (MotionVectorPassOutput)0;
    output = BuildVaryings(input, currentFrameMvData);
    packedOutput = PackVaryings(output);

#if defined(HAVE_VFX_MODIFICATION) && !VFX_FEATURE_MOTION_VECTORS
    //Motion vector is enabled in SG but not active in VFX
    const bool forceNoMotion = true;
#else
    const bool forceNoMotion = unity_MotionVectorsParams.y == 0.0;
#endif

    if (!forceNoMotion)
    {
#if defined(HAVE_VFX_MODIFICATION)
    float3 prevPosOS = currentFrameMvData.vfxParticlePositionOS;
    #if defined(VFX_FEATURE_MOTION_VECTORS_VERTS)
        const bool applyDeformation = false;
    #else
        const bool applyDeformation = true;
    #endif
#else
    const bool hasDeformation = unity_MotionVectorsParams.x == 1; // Mesh has skinned deformation
    float3 prevPosOS = hasDeformation ? passInput.prevPosOS : input.positionOS;

    #if defined(AUTOMATIC_TIME_BASED_MOTION_VECTORS) && defined(GRAPH_VERTEX_USES_TIME_PARAMETERS_INPUT)
        const bool applyDeformation = true;
    #else
        const bool applyDeformation = hasDeformation;
    #endif
#endif

#if defined(FEATURES_GRAPH_VERTEX)
    if (applyDeformation)
        prevPosOS = GetLastFrameDeformedPosition(input, currentFrameMvData, prevPosOS);
    else
        prevPosOS = currentFrameMvData.positionOS;

    #if defined(FEATURES_GRAPH_VERTEX_MOTION_VECTOR_OUTPUT)
        prevPosOS -= currentFrameMvData.motionVector;
    #endif
#endif

#if defined(UNITY_DOTS_INSTANCING_ENABLED) && defined(DOTS_DEFORMED)
    // Deformed vertices in DOTS are not cumulative with built-in Unity skinning/blend shapes
    // Needs to be called after vertex modification has been applied otherwise it will be
    // overwritten by Compute Deform node
    ApplyPreviousFrameDeformedVertexPosition(input.vertexID, prevPosOS);
#endif
        
    mvOutput.posCSNoJitter = mul(_NonJitteredViewProjMatrix, float4(currentFrameMvData.positionWS, 1.0f));

#if defined(HAVE_VFX_MODIFICATION)
    #if defined(VFX_FEATURE_MOTION_VECTORS_VERTS)
        #if defined(FEATURES_GRAPH_VERTEX_MOTION_VECTOR_OUTPUT)
            #error Unexpected fast path rendering VFX motion vector while there are vertex modification afterwards.
        #endif
        mvOutput.prevPosCSNoJitter = VFXGetPreviousClipPosition(input, currentFrameMvData.vfxElementAttributes, mvOutput.posCSNoJitter);
    #else
        #if VFX_WORLD_SPACE
            //prevPosOS is already in world space
            const float3 previousPositionWS = prevPosOS;
        #else
            const float3 previousPositionWS = mul(UNITY_PREV_MATRIX_M, float4(prevPosOS, 1.0f)).xyz;
        #endif
        mvOutput.prevPosCSNoJitter = mul(_PrevViewProjMatrix, float4(previousPositionWS, 1.0f));
    #endif
#else
        mvOutput.prevPosCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, float4(prevPosOS, 1.0f)));
#endif
    }

    packedMvOutput = PackMotionVectorVaryings(mvOutput);
}

float4 frag(
    PackedMotionVectorPassVaryings packedMvInput,
    PackedVaryings packedInput) : SV_Target
{
    Varyings unpackedInput = UnpackVaryings(packedInput);
    MotionVectorPassVaryings unPackedMvInput = UnpackMotionVectorVaryings(packedMvInput);
    UNITY_SETUP_INSTANCE_ID(unpackedInput);
    SurfaceDescription surfaceDescription = BuildSurfaceDescription(unpackedInput);

#if defined(_ALPHATEST_ON)
    clip(surfaceDescription.Alpha - surfaceDescription.AlphaClipThreshold);
#endif

#if defined(LOD_FADE_CROSSFADE) && USE_UNITY_CROSSFADE
    LODFadeCrossFade(unpackedInput.positionCS);
#endif

    return float4(CalcNdcMotionVectorFromCsPositions(unPackedMvInput.posCSNoJitter, unPackedMvInput.prevPosCSNoJitter), 0, 0);
}
#endif
