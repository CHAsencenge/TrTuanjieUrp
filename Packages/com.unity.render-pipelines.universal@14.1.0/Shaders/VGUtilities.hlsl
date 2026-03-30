#ifndef UNIVERSAL_VG_UTILITIES_INCLUDED
#define UNIVERSAL_VG_UTILITIES_INCLUDED

Texture2D<uint4> _VisibilityBuffer;

void GetFragDataEX(in float2 uv,
    in uint clusterID,
    in uint triangleID,
    out FRONT_FACE_TYPE cullFace,
    out float3 localPosition,
    out float4 positionCS,
    out float4x4 local2WorldMatrix,
    out float4x4 world2LocalMatrix,
    out VGClusterData cluster,
    out PixelAttribute attributeData,
    out InstanceSubset instance,
    out uint instanceId,
    out uint materialOffset)
{
    SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
    cluster = LoadCluster(survivalCluster.pageIndex, survivalCluster.clusterIndex);
    instance = _InstanceSubsetBuffer[survivalCluster.instanceId];
    instanceId = survivalCluster.instanceId;
    GPUView view = GetView(survivalCluster.ViewId);
    uint materialIndex = GetRelativeMaterialIndex(cluster, triangleID);
    materialOffset = _MaterialSlotBuffer[instance.materialSlotOffset + materialIndex * 2 + 1];
    local2WorldMatrix = MakeInstanceMatrix(instance);
    world2LocalMatrix = Inverse(local2WorldMatrix);
    uint pageClusterCount = GetClusterCount(_ClusterPageData, Convert2GPUOffset(survivalCluster.pageIndex));

    const uint3 triIndices = ReadTriangleIndices(cluster, triangleID);
    float3 pointLocal0 = DecodePosition(triIndices.x, cluster);
    float3 pointLocal1 = DecodePosition(triIndices.y, cluster);
    float3 pointLocal2 = DecodePosition(triIndices.z, cluster);

#ifdef GPU_VERTEX_ANIMATION
    bool isCameraRelative = false;
#ifdef VBUFFER_CAMERA_RELATIVE_RENDERING
    isCameraRelative = true;
#endif //VBUFFER_CAMERA_RELATIVE_RENDERING

    VBufferVertexAttribute vertex0 = GetVBufferVertexAttribute(cluster, triIndices.x, pageClusterCount);
    VBufferVertexAttribute vertex1 = GetVBufferVertexAttribute(cluster, triIndices.y, pageClusterCount);
    VBufferVertexAttribute vertex2 = GetVBufferVertexAttribute(cluster, triIndices.z, pageClusterCount);
    VGApplyVertexAnimation(pointLocal0, vertex0, view, local2WorldMatrix, _WorldSpaceCameraPos.xyz, isCameraRelative, triIndices.x, instance, survivalCluster.instanceId, materialOffset);
    VGApplyVertexAnimation(pointLocal1, vertex1, view, local2WorldMatrix, _WorldSpaceCameraPos.xyz, isCameraRelative, triIndices.y, instance, survivalCluster.instanceId, materialOffset);
    VGApplyVertexAnimation(pointLocal2, vertex2, view, local2WorldMatrix, _WorldSpaceCameraPos.xyz, isCameraRelative, triIndices.z, instance, survivalCluster.instanceId, materialOffset);
#endif // GPU_VERTEX_ANIMATION
    
    float4x4 mvp = mul(view.viewProjectionMatrix, local2WorldMatrix);
    float4 clipPos0 = mul(mvp, float4(pointLocal0, 1.0));
    float4 clipPos1 = mul(mvp, float4(pointLocal1, 1.0));
    float4 clipPos2 = mul(mvp, float4(pointLocal2, 1.0));

    float2 screenSize = view.viewPort.zw - view.viewPort.xy;
    uv -= view.viewPort.xy;
    const float2 pixelClip = uv * (1 / screenSize) * float2(2, 2) + float2(-1, -1);

    Barycentrics barycentrics = CalculateTriangleBarycentrics(pixelClip, clipPos0, clipPos1, clipPos2, screenSize);
#ifdef GPU_VERTEX_ANIMATION
    attributeData = GetPixelAttribute(cluster, vertex0, vertex1, vertex2, barycentrics, (float3x3)local2WorldMatrix, (float3x3)world2LocalMatrix);
#else
    attributeData = GetPixelAttribute(cluster, triIndices, barycentrics, pageClusterCount, (float3x3)local2WorldMatrix, (float3x3)world2LocalMatrix);
#endif // GPU_VERTEX_ANIMATION


    if (cluster.uvCount == 1)
    {
        attributeData.texCoords[1] = attributeData.texCoords[0];
        attributeData.texCoordsDDX[1] = attributeData.texCoordsDDX[0];
        attributeData.texCoordsDDY[1] = attributeData.texCoordsDDY[0];
    }

    localPosition = barycentrics.UVW.x * pointLocal0 +
        barycentrics.UVW.y * pointLocal1 +
        barycentrics.UVW.z * pointLocal2;

    positionCS = barycentrics.UVW.x * clipPos0 + barycentrics.UVW.y * clipPos1 + barycentrics.UVW.z * clipPos2;
#if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
    cullFace = !IsCCW(instance.mask);
    float3 v0 = local2world(local2WorldMatrix, pointLocal0);
    float3 v1 = local2world(local2WorldMatrix, pointLocal1);
    float3 v2 = local2world(local2WorldMatrix, pointLocal2);
    if (isBackFacing(v0, v1, v2, view, false))
    {
        cullFace = !cullFace;
    }
#else
    cullFace = true;
#endif
}

// In URP, only Shader Graph will use this macro.
#ifdef SHADERPASS
#undef VaryingsType
#if SHADERPASS == SHADERPASS_GBUFFER_SPLAT
#define VaryingsType VaryingsVG
#elif SHADERPASS == SHADERPASS_VBUFFER_ALPHA_CLIP || SHADERPASS == SHADERPASS_ALPHA_MESH_SELECTION || SHADERPASS == SHADERPASS_VGSHADOWMAP_ALPHA_CLIP
#define VaryingsType VaryingsBinning
#endif

#if SHADERPASS == SHADERPASS_VBUFFER_ALPHA_CLIP || SHADERPASS == SHADERPASS_ALPHA_MESH_SELECTION || SHADERPASS == SHADERPASS_VGSHADOWMAP_ALPHA_CLIP
// The parameter, named uv, in BuildVaryingsTexCoords means uv0 of interpolation in VS,
// while the parameter, named uv, in BuildVaryings below means the uv of full screen.
Varyings BuildVaryingsTexCoords(VaryingsBinning input, out float4x4 local2WorldMatrix, out float4x4 world2LocalMatrix, out InstanceSubset instance, out uint instanceId)
{
    uint clusterID  = GetVisibleClusterID(input.visibility.x);

    Varyings output = (Varyings)0;

    SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
    instance = _InstanceSubsetBuffer[survivalCluster.instanceId];
    instanceId = survivalCluster.instanceId;
    local2WorldMatrix = MakeInstanceMatrix(instance);
    world2LocalMatrix = Inverse(local2WorldMatrix);

    // Now only positionCS and uv0 in Varyings is essential for Alpha Clip in Shader Graph.
    output.positionCS = float4(input.positionCS.xyz / input.positionCS.w, 1.0);

#ifdef VBUFFER_NEED_TEXCOORD0
    output.texCoord0.xy = input.uv0.xy;
#endif

    return output;
}
#endif

Varyings BuildVaryings(uint2 uv, uint clusterID, uint triangleID, out InstanceSubset instance, out uint instanceId, out PixelAttribute attributeData, out uint materialOffset, out float4x4 local2WorldMatrix, out float4x4 world2LocalMatrix)
{
    Varyings output = (Varyings)0;
    FRONT_FACE_TYPE cullFace;
    float3 localPosition;
    float4 positionCS;
    VGClusterData cluster;
    GetFragDataEX(uv, clusterID, triangleID, cullFace, localPosition, positionCS, local2WorldMatrix, world2LocalMatrix, cluster, attributeData, instance, instanceId, materialOffset);

    float3 positionWS = mul(local2WorldMatrix, float4(localPosition, 1.0f)).xyz;
    float3 normalWS = attributeData.normalWS;

    output.positionCS = float4(positionCS.xyz / positionCS.w, 1.0);

#ifdef VARYINGS_NEED_POSITION_WS
    output.positionWS = positionWS;
#endif

#ifdef VARYINGS_NEED_NORMAL_WS
    output.normalWS = normalWS;
#endif

#ifdef VARYINGS_NEED_TANGENT_WS
    real oddNegativeScale = determinant(local2WorldMatrix) > 0.0f ? 1.0f : -1.0f;
    real sign = oddNegativeScale * (attributeData.tangentWS.w > 0.0f ? 1.0f : -1.0f);
    output.tangentWS = half4(attributeData.tangentWS.xyz, sign); // must not be normalized (mikkts requirement)
#endif

#ifdef VARYINGS_NEED_TEXCOORD0
    output.texCoord0.xy = attributeData.texCoords[0];
#endif

#ifdef VARYINGS_NEED_TEXCOORD1
    output.texCoord1.xy = attributeData.texCoords[1];
#endif

#ifdef VARYINGS_NEED_TEXCOORD2
    output.texCoord2.xy = attributeData.texCoords[2];
#endif

#ifdef VARYINGS_NEED_TEXCOORD3
    output.texCoord3.xy = attributeData.texCoords[3];
#endif

#ifdef VARYINGS_NEED_COLOR
    output.color = attributeData.vertexColor;
#endif

#if defined(SHADER_STAGE_FRAGMENT) && defined(VARYINGS_NEED_CULLFACE)
    output.cullFace = cullFace;
#endif

#ifdef LIGHTMAP_ON
    OUTPUT_LIGHTMAP_UV(attributeData.texCoords[1], unity_LightmapST, output.staticLightmapUV);
#else
    // Actually, there's no need to calculate this within the vert stage for VG.
    // OUTPUT_SH(normalWS.xyz, output.sh);
#endif

#ifdef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
    VertexPositionInputs vertexInput = GetVertexPositionInputs(localPosition);
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

#ifdef VARYINGS_NEED_FOG_AND_VERTEX_LIGHT
    half fogFactor = 0;
#ifndef _FOG_FRAGMENT
    fogFactor = ComputeFogFactor(output.positionCS.z);
#endif
    half3 vertexLight = VertexLighting(positionWS, normalize(normalWS));
    output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
#endif

    return output;
}
#endif

#endif
