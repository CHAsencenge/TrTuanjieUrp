
#include "GPUDrivenVertexAnimation.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/VGUtilities.hlsl"

void InitializeInputData(Varyings input,
    SurfaceDescription surfaceDescription,
    InstanceSubset instance,
    PixelAttribute attributeData,
    float4x4 local2WorldMatrix,
    out InputData inputData)
{
    inputData = (InputData)0;

    inputData.positionWS = input.positionWS;
    inputData.positionCS = input.positionCS;

#ifdef _NORMALMAP
    float oddNegativeScale = determinant(local2WorldMatrix) > 0.0f ? 1.0f : -1.0f;
    float crossSign = (input.tangentWS.w > 0.0 ? 1.0 : -1.0) * oddNegativeScale;
    float3 bitangent = crossSign * cross(input.normalWS.xyz, input.tangentWS.xyz);

    inputData.tangentToWorld = half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz);
#if _NORMAL_DROPOFF_TS
    inputData.normalWS = TransformTangentToWorld(surfaceDescription.NormalTS, inputData.tangentToWorld);
#elif _NORMAL_DROPOFF_OS
    inputData.normalWS = TransformObjectToWorldNormal(surfaceDescription.NormalOS);
#elif _NORMAL_DROPOFF_WS
    inputData.normalWS = surfaceDescription.NormalWS;
#endif
#else
    inputData.normalWS = input.normalWS;
#endif
    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

#ifdef MAIN_LIGHT_CALCULATE_SHADOWS
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif

    inputData.fogCoord = InitializeInputDataFog(float4(input.positionWS, 1.0), input.fogFactorAndVertexLight.x);
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;

    float2 ddx = attributeData.texCoordsDDX[1].xy * unity_LightmapST.xy;
    float2 ddy = attributeData.texCoordsDDY[1].xy * unity_LightmapST.xy;
    inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.sh, inputData.normalWS, ddx, ddy, inputData.positionWS, inputData.shadowMask, instance);

    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

    //inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV, ddx, ddy);

#ifdef DEBUG_DISPLAY
#ifdef LIGHTMAP_ON
    inputData.staticLightmapUV = input.staticLightmapUV;
#else
    inputData.vertexSH = input.sh;
#endif
#endif
}

VaryingsVG vert(AttributesVG inputMesh)
{
    VaryingsVG output = (VaryingsVG)0;
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

FragmentOutput frag(VaryingsVG input)
{
    InstanceSubset instance;
    PixelAttribute attributeData;
    uint instanceId;
    uint materialOffset;
    float4x4 local2WorldMatrix;
    float4x4 world2LocalMatrix;

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

    Varyings varyings = BuildVaryings(uv, clusterID, triangleID, instance, instanceId, attributeData, materialOffset, local2WorldMatrix, world2LocalMatrix);
    SurfaceDescription surfaceDescription = BuildSurfaceDescription(varyings, instance, instanceId, materialOffset, local2WorldMatrix, world2LocalMatrix, attributeData);

#if _SURFACE_TYPE_TRANSPARENT
    half alpha = surfaceDescription.Alpha;
#else
    half alpha = 1;
#endif

#if defined(LOD_FADE_CROSSFADE) && USE_UNITY_CROSSFADE
    LODFadeCrossFade(varyings.positionCS);
#endif

    InputData inputData;
    InitializeInputData(varyings, surfaceDescription, instance, attributeData, local2WorldMatrix, inputData);

#ifdef _SPECULAR_SETUP
    float3 specular = surfaceDescription.Specular;
    float metallic = 1;
#else
    float3 specular = 0;
    float metallic = surfaceDescription.Metallic;
#endif

#ifdef _DBUFFER
    ApplyDecal(input.positionCS,
        surfaceDescription.BaseColor,
        specular,
        inputData.normalWS,
        metallic,
        surfaceDescription.Occlusion,
        surfaceDescription.Smoothness);
#endif

    BRDFData brdfData;
    InitializeBRDFData(surfaceDescription.BaseColor, metallic, specular, surfaceDescription.Smoothness, alpha, brdfData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, inputData.shadowMask);
    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, inputData.shadowMask);
    half3 color = GlobalIllumination(brdfData, inputData.bakedGI, surfaceDescription.Occlusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS, instance);

    return BRDFDataToGbuffer(brdfData, inputData, surfaceDescription.Smoothness, surfaceDescription.Emission + color, instance, surfaceDescription.Occlusion);
}
