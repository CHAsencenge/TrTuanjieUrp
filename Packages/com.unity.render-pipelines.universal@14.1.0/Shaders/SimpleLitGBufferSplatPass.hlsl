#ifndef UNIVERSAL_SIMPLELIT_GBUFFER_PASS_INCLUDED
#define UNIVERSAL_SIMPLELIT_GBUFFER_PASS_INCLUDED

#if defined(_NORMALMAP)
#define REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR
#endif

struct FragmentData
{
    float2 uv;

    float3 positionWS;

    half3 normalWS;

#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    half4 tangentWS;
#endif

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    half3 vertexLighting;
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    float4 shadowCoord;
#endif

#if defined(LIGHTMAP_ON)
    float2 staticLightmapUV;
#else
    half3 vertexSH;
#endif

    float4 positionCS;
};

FragmentData GetFragmentData(float2 uv, uint clusterID, uint triangleID, out PixelAttribute attributeData, out InstanceSubset instance, out uint materialOffset)
{
    FragmentData output;
    ZERO_INITIALIZE(FragmentData, output);

    FRONT_FACE_TYPE cullFace;
    float3 localPosition;
    float4 positionCS;
    float4x4 local2WorldMatrix;
    float4x4 world2LocalMatrix;
    VGClusterData cluster;
    uint instanceId;
    GetFragDataEX(uv, clusterID, triangleID, cullFace, localPosition, positionCS, local2WorldMatrix, world2LocalMatrix, cluster, attributeData, instance, instanceId, materialOffset);

    output.uv = TRANSFORM_TEX(attributeData.texCoords[0], _BaseMap);

    output.positionWS = mul(local2WorldMatrix, float4(localPosition, 1.0f)).xyz;

    output.normalWS = attributeData.normalWS;

#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR)
    real oddNegativeScale = determinant(local2WorldMatrix) > 0.0f ? 1.0f : -1.0f;
    real sign = oddNegativeScale * (attributeData.tangentWS.w > 0.0f ? 1.0f : -1.0f);
    output.tangentWS = half4(attributeData.tangentWS.xyz, sign); // must not be normalized (mikkts requirement)
#endif

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    output.vertexLighting = VertexLighting(output.positionWS, normalize(output.normalWS));
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    VertexPositionInputs vertexInput = GetVertexPositionInputs(localPosition);
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

    OUTPUT_LIGHTMAP_UV(attributeData.texCoords[1], unity_LightmapST, output.staticLightmapUV);
    // Actually, there's no need to calculate this within the vert stage for VG.
    // OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

    output.positionCS = float4(positionCS.xyz / positionCS.w, 1.0);

    return output;
}

void InitializeInputData(FragmentData input, half3 normalTS, out InputData inputData, PixelAttribute attributeData, InstanceSubset instance)
{
    inputData = (InputData)0;

    inputData.positionWS = input.positionWS;
    inputData.positionCS = input.positionCS;
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

    #ifdef _NORMALMAP
        float sgn = input.tangentWS.w;      // should be either +1 or -1
        float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
        inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz));
    #else
        inputData.normalWS = input.normalWS;
    #endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
        inputData.shadowCoord = input.shadowCoord;
    #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
    #else
        inputData.shadowCoord = float4(0, 0, 0, 0);
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.vertexLighting = input.vertexLighting.xyz;
    #else
        inputData.vertexLighting = half3(0, 0, 0);
    #endif

    inputData.fogCoord = 0; // we don't apply fog in the gbuffer pass

    float2 ddx = attributeData.texCoordsDDX[1].xy * unity_LightmapST.xy;
    float2 ddy = attributeData.texCoordsDDY[1].xy * unity_LightmapST.xy;
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS, ddx, ddy, inputData.positionWS, inputData.shadowMask, instance);

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

    #if defined(DEBUG_DISPLAY)
    #if defined(LIGHTMAP_ON)
    inputData.staticLightmapUV = input.staticLightmapUV;
    #else
    inputData.vertexSH = input.vertexSH;
    #endif
    #endif
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

VaryingsVG SimpleLitGBufferSplatPassVertexSimple(AttributesVG inputMesh)
{
    VaryingsVG output;
    UNITY_SETUP_INSTANCE_ID(inputMesh);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
#ifdef PROCEDURAL_INSTANCING_ON
    float remap[6] = {0, 2, 1, 3, 2, 0};
    uint quadIndex = remap[inputMesh.vertexID];
    output.positionCS = GetTileVertexPosition(quadIndex, inputMesh.instanceID, _TileSizeAndTargetSize.xy, _ScreenSize.xy);
    output.positionCS.y *= -1.0;
    uint materialID = asuint(_CurrentMaterialID);
    output.positionCS.z = asfloat(materialID);
    output.texcoord = GetTileTexCoord(quadIndex, inputMesh.instanceID, _TileSizeAndTargetSize.xy, _ScreenSize.xy);
    uint4 range = _MaterialRangeBuffer[inputMesh.instanceID];
    uint curMaterialID = materialID & 0x00003FFF;
    uint slot = curMaterialID % 64;
    if (ReadBits(range, slot, 1) != 1)
    {
        output.positionCS.xy = asfloat(0xFFFFFFFF);
    }
#else
    output.positionCS = float4(0, 0, -1, 1);
    output.texcoord = float2(0, 0);
#endif
    return output;
}

FragmentOutput SimpleLitGBufferSplatPassFragmentSimple(VaryingsVG input)
{
    uint2 uv = input.positionCS.xy;
    uint pixelValue = LOAD_TEXTURE2D(_VisibilityBuffer, uv).r;
    uint clusterID = GetVisibleClusterID(pixelValue);
    uint triangleID = GetTriangleID(pixelValue);
    uint materialID = GetMaterialID(clusterID, triangleID);
    if (materialID != asuint(_CurrentMaterialID))
    {
        FragmentOutput output = (FragmentOutput)0;
        return output;
    }

    uint materialOffset;
    PixelAttribute attributeData;
    InstanceSubset instance;

    FragmentData fragData = GetFragmentData(input.positionCS.xy, clusterID, triangleID, attributeData, instance, materialOffset);

    SurfaceData surfaceData;
    float2 ddx = attributeData.texCoordsDDX[0].xy;
    float2 ddy = attributeData.texCoordsDDY[0].xy;
    InitializeSimpleLitSurfaceData(fragData.uv, surfaceData, materialOffset, ddx, ddy);

    InputData inputData;
    InitializeInputData(fragData, surfaceData.normalTS, inputData, attributeData, instance);
    SETUP_DEBUG_TEXTURE_DATA(inputData, fragData.uv, _BaseMap);

#ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData, attributeData, instance);
#endif

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, inputData.shadowMask);
    half4 color = half4(inputData.bakedGI * surfaceData.albedo + surfaceData.emission, surfaceData.alpha);

    return SurfaceDataToGbuffer(surfaceData, inputData, color.rgb, kLightingSimpleLit, instance);
};

#endif
