#ifndef UNIVERSAL_LIT_GBUFFERSPLAT_PASS_INCLUDED
#define UNIVERSAL_LIT_GBUFFERSPLAT_PASS_INCLUDED

#if defined(_PARALLAXMAP) && (SHADER_TARGET >= 30)
#define REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR
#endif

#if (defined(_NORMALMAP) || (defined(_PARALLAXMAP) && !defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR))) || defined(_DETAIL)
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

#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirTS;
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

#if defined(REQUIRES_WORLD_SPACE_TANGENT_INTERPOLATOR) || defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
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

#if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(output.positionWS);
    output.viewDirTS = GetViewDirectionTangentSpace(output.tangentWS, output.normalWS, viewDirWS);
#endif

    OUTPUT_LIGHTMAP_UV(attributeData.texCoords[1], unity_LightmapST, output.staticLightmapUV);
    // Actually, there's no need to calculate this within the vert stage for VG.
    // OUTPUT_SH(output.normalWS.xyz, output.vertexSH, true);

    output.positionCS = float4(positionCS.xyz / positionCS.w, 1.0);

    return output;
}

void InitializeInputData(FragmentData input, half3 normalTS, out InputData inputData, PixelAttribute attributeData, InstanceSubset instance)
{
    inputData = (InputData)0;

    inputData.positionWS = input.positionWS;
    inputData.positionCS = input.positionCS;
    half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    #if defined(_NORMALMAP) || defined(_DETAIL)
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

    inputData.fogCoord = 0.0; // we don't apply fog in the guffer pass

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        inputData.vertexLighting = input.vertexLighting.xyz;
    #else
        inputData.vertexLighting = half3(0, 0, 0);
    #endif

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

VaryingsVG LitGBufferSplatPassVertex(AttributesVG inputMesh)
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



FragmentOutput LitGBufferSplatPassFragment(VaryingsVG input)
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

#if defined(_PARALLAXMAP)
    #if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
        half3 viewDirTS = fragData.viewDirTS;
    #else
        half3 viewDirWS = GetWorldSpaceNormalizeViewDir(fragData.positionWS);
        half3 viewDirTS = GetViewDirectionTangentSpace(fragData.tangentWS, fragData.normalWS, viewDirWS);
    #endif
    ApplyPerPixelDisplacement(viewDirTS, fragData.uv, materialOffset);
#endif

    SurfaceData surfaceData;
    float2 ddx = attributeData.texCoordsDDX[0].xy;
    float2 ddy = attributeData.texCoordsDDY[0].xy;
    InitializeStandardLitSurfaceData(fragData.uv, surfaceData, materialOffset, ddx, ddy);

    InputData inputData;
    InitializeInputData(fragData, surfaceData.normalTS, inputData, attributeData, instance);
    SETUP_DEBUG_TEXTURE_DATA(inputData, fragData.uv, _BaseMap);

#ifdef _DBUFFER
    ApplyDecalToSurfaceData(input.positionCS, surfaceData, inputData);
#endif

    BRDFData brdfData;
    InitializeBRDFData(surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.alpha, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, inputData.shadowMask);
    half3 color = GlobalIllumination(brdfData, inputData.bakedGI, surfaceData.occlusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS, instance);

    return BRDFDataToGbuffer(brdfData, inputData, surfaceData.smoothness, surfaceData.emission + color, instance, surfaceData.occlusion);
}



#endif
