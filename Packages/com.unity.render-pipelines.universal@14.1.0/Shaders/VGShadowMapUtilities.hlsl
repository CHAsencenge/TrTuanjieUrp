#ifndef UNIVERSAL_VG_SHADOW_MAP_UTILITIES_INCLUDED
#define UNIVERSAL_VG_SHADOW_MAP_UTILITIES_INCLUDED

float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirection, float2 shadowBias)
{
    float invNdotL = 1.0 - saturate(dot(lightDirection, normalWS));
    float scale = invNdotL * shadowBias.y;

    // normal bias is negative since we want to apply an inset normal offset
    positionWS = lightDirection * shadowBias.xxx + positionWS;
    positionWS = normalWS * scale.xxx + positionWS;
    return positionWS;
}

VaryingsBinning GetVaryingsBinningDataWithShadowBias(uint instanceIndex, uint vertexIndex)
{
    VaryingsBinning OUT = (VaryingsBinning)0;
    OUT.positionCS = asfloat(0xFFFFFFFF);

	PackedBucketData packedBucketData = GetVisibleIndexAndTriRangeHw(instanceIndex);
    uint clusterID = packedBucketData.clusterIndex;
    uint relativeTriIndex = vertexIndex / 3;
    if (relativeTriIndex >= packedBucketData.triNum)
        return OUT;

    SurvivalCluster survivalCluster = LoadSurvivalCluster(clusterID);
    VGClusterData cluster = LoadCluster(survivalCluster.pageIndex, survivalCluster.clusterIndex);
    const uint triIndex = packedBucketData.triStart + relativeTriIndex;
    InstanceSubset instance = _InstanceSubsetBuffer[survivalCluster.instanceId];
    float4x4 local2WorldMatrix = MakeInstanceMatrix(instance);
    GPUView view = GetView(survivalCluster.ViewId);
    uint relativeMaterialIndex = GetRelativeMaterialIndex(cluster, triIndex);
    uint materialOffset = _MaterialSlotBuffer[instance.materialSlotOffset + relativeMaterialIndex * 2 + 1];
    uint pageClusterCount = GetClusterCount(_ClusterPageData, Convert2GPUOffset(survivalCluster.pageIndex));
    bool isCameraRelative = false;
#ifdef VBUFFER_CAMERA_RELATIVE_RENDERING
    ApplyViewTranslationToMatrix(local2WorldMatrix, _WorldSpaceCameraPos.xyz);
    isCameraRelative = true;
#endif

    {
        uint3 triIndices = ReadTriangleIndices(cluster.pageAddress, cluster.indexDataOffset, cluster.indexBits, triIndex);
        if (IsCCW(instance.mask))
            triIndices = uint3(triIndices.x, triIndices.z, triIndices.y);
        // Perform backface/frontface culling in HClip space
        if (_ShadowPassCullMode > 0 && IsShadowCastingTwoSided(instance.mask))
        {
            float3 v0 = local2world(local2WorldMatrix, DecodePosition(triIndices[0], cluster));
            float3 v1 = local2world(local2WorldMatrix, DecodePosition(triIndices[1], cluster));
            float3 v2 = local2world(local2WorldMatrix, DecodePosition(triIndices[2], cluster));
#ifdef VBUFFER_CAMERA_RELATIVE_RENDERING
            bool backfacing = isBackFacing(v0, v1, v2, view, true);
#else
            bool backfacing = isBackFacing(v0, v1, v2, view, false);
#endif
            bool cullBack = _ShadowPassCullMode == 2;
            bool cullFront = _ShadowPassCullMode == 1;
            bool setWindingOrder = (backfacing && cullBack) || (!backfacing && cullFront);
            triIndices = setWindingOrder ? uint3(triIndices.x, triIndices.z, triIndices.y) : triIndices;
        }

        int vertIndexInTri = vertexIndex - relativeTriIndex * 3;
        uint vertIndexInCluster = triIndices[vertIndexInTri];
        float3 positionOS = DecodePosition(vertIndexInCluster, cluster);
#ifdef GPU_VERTEX_ANIMATION
        VBufferVertexAttribute vertexAttribute = GetVBufferVertexAttribute(cluster, vertIndexInCluster, pageClusterCount);
        VGApplyVertexAnimation(positionOS, vertexAttribute, view, local2WorldMatrix, _WorldSpaceCameraPos.xyz, isCameraRelative, vertIndexInCluster, instance, survivalCluster.instanceId, materialOffset);
#endif
        float3 positionWS = mul(local2WorldMatrix, float4(positionOS, 1.0f)).xyz;

        uint attributeDataAddress = cluster.pageAddress + cluster.attributeDataOffset;
#if VG_ENABLE_UNCOMPRESSED_ENCODE_VERTEX_DATA
        uint readOffset = attributeDataAddress + vertIndexInCluster * cluster.attributeBits / 8;
        float3 normalOS = asfloat(_ClusterPageData.Load3(readOffset));

        // Update readOffset for next usage.
        readOffset += cluster.tangentMode == VG_CLUSTER_TANGENT_MODE_ENCODE ? 28 : 12;
#elif VG_ENABLE_FIXED_ENCODE_VERTEX_DATA
        uint readOffset = attributeDataAddress + vertIndexInCluster * cluster.attributeBits / 8;
        float3 normalOS = DecodeNormalUnitVector(_ClusterPageData.Load(readOffset));
        readOffset += 4;

#ifdef GPU_ALPHA_CLIP_ON
        if (cluster.tangentMode == VG_CLUSTER_TANGENT_MODE_ENCODE)
        {
            readOffset += 4;
        }
#endif
#else
        uint uvCount = max(1, min(MAX_NUM_UVS, cluster.uvCount));
        uint maxAttributeBits = CalculateMaxAttributeBits(uvCount);
        StreamerReader streamReader = CreateAlignedStreamReader(_ClusterPageData, attributeDataAddress, vertIndexInCluster * cluster.attributeBits, maxAttributeBits);
        uint normalBits = ReadStream(streamReader, 2 * cluster.normalBits, 2 * MAX_BITS_FOR_ENCODED_NORMAL);
        float3 normalOS = DecodeUnitVector(normalBits, cluster.normalBits);

        // Although this data is useless for shadow map, we should still read it to update StreamReader
        // when Alpha Clip enabled.
#ifdef GPU_ALPHA_CLIP_ON
        // Update StreamReader's state for next usage.
        if (cluster.tangentMode == VG_CLUSTER_TANGENT_MODE_ENCODE)
        {
            uint tangentBits = ReadStream(streamReader, 2 * cluster.tangentBits + VG_CLUSTER_BITANGNET_BITS, 2 * MAX_BITS_FOR_ENCODED_TANGENT + VG_CLUSTER_BITANGNET_BITS);
        }
        else
        {
            UpdateStream(streamReader, 2 * MAX_BITS_FOR_ENCODED_TANGENT + VG_CLUSTER_BITANGNET_BITS);
        }
#endif

#endif
        float4x4 world2LocalMatrix = Inverse(local2WorldMatrix);
        float3 normalWS = mul(float4(normalOS, 0.0f), world2LocalMatrix).xyz;
        normalWS = normalize(normalWS);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
        float3 lightDirectionWS = normalize(view.lightPosition.xyz - positionWS);
#else
        float3 lightDirectionWS = view.lightDirection.xyz;
#endif

        float2 shadowBias = float2(view.lightDirection.w, view.lightPosition.w);
        // @TODO: Now shadow bias in VG Shadow will cause some voids in shadow. We may consider
        // another way to calculate shadow bias.
        // We use two float4 to include _ShadowBias, _LightDirection and _LightPosition.
        // Only the x and y in shadow bias is effective, so we store them separately by
        // the w of light direction and light position.
        float3 positionWSBias = ApplyShadowBias(positionWS, normalWS, lightDirectionWS, shadowBias);

        float4 positionCS = mul(view.viewProjectionMatrix, float4(positionWSBias, 1));
#if MULTI_VIEW
        // avoid adjusting viewport in single view
        if (!all(view.viewPort == 0) && !all(view.viewSizeAndInvSize == 0))
        {
            OUT.viewPort = view.viewPort;
            positionCS.xy = (view.viewPort.zw - view.viewPort.xy) * (positionCS.xy + positionCS.w) + (view.viewPort.xy - view.viewSizeAndInvSize.xy / 2) * 2 * positionCS.w;
            positionCS.xy /= view.viewSizeAndInvSize.xy;
        }
#endif

#if UNITY_UV_STARTS_AT_TOP
        positionCS.y = -positionCS.y;
#endif

        // UV0 is in need in Alpha Clip to sample.
#ifdef VBUFFER_NEED_TEXCOORD0
#if VG_ENABLE_UNCOMPRESSED_ENCODE_VERTEX_DATA
        // Skip vertex color
        readOffset += 4;

        OUT.uv0 = asfloat(_ClusterPageData.Load2(readOffset));
        readOffset += 8;
#elif VG_ENABLE_FIXED_ENCODE_VERTEX_DATA
        if (cluster.colorBits != 0)
        {
            readOffset += 4;
        }

        const uint uvIndex = 0;
        uint uvParamsAddr = cluster.pageAddress + cluster.uvParamsOffset;
        uint pageClusterCount = GetClusterCount(_ClusterPageData, Convert2GPUOffset(survivalCluster.pageIndex));
        UVParams uvParams = GetUVParams(_ClusterPageData, uvParamsAddr, pageClusterCount, uvIndex);

        float2 texCoord = UncompressedToFloat(_ClusterPageData.Load(readOffset)) + uvParams.minUV;
        readOffset += 4;

        OUT.uv0 = texCoord;
#else
        // Skip vertex color
        uint4 numComponentBits = Unpack2Uint4(cluster.colorBits, 4);
        uint4 colorDelta = ReadStream4(streamReader, numComponentBits, MAX_BITS_FOR_ENCODED_COLOR);

        const uint uvIndex = 0;
        uint2 uvBits = uint2(BitFieldExtractU32(cluster.uvBits, UV_BITS_BITS, uvIndex * 2 * UV_BITS_BITS + UV_BITS_BITS), BitFieldExtractU32(cluster.uvBits, UV_BITS_BITS, uvIndex * 2 * UV_BITS_BITS));
        uvBits = ReadStream2(streamReader, uvBits, MAX_BITS_FOR_ENCODED_UV);

        uint uvParamsAddr = cluster.pageAddress + cluster.uvParamsOffset;
        UVParams uvParams = GetUVParams(_ClusterPageData, uvParamsAddr, pageClusterCount, uvIndex);

        float2 texCoord = UnpackTexCoord(uvBits, uvParams);
        OUT.uv0 = texCoord;
#endif
#endif

#ifdef GPU_ALPHA_CLIP_ON
        // When Alpha Clip enabled, we need cluster and triangle id to
        // get material offset and load alpha value in Shader Graph.
        OUT.visibility.x = clusterID + 1;
        OUT.visibility.x |= triIndex << 25;
        OUT.visibility.y = materialOffset;
#endif

        OUT.positionCS = positionCS;
    }

    return OUT;
}

#endif
