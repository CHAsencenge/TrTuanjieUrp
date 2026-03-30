using System;
using UnityEngine.Assertions;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;

namespace UnityEngine.Rendering.Universal.Internal
{
    /// <summary>
    /// Renders a shadow map for the main Light.
    /// </summary>
    public class MainLightShadowCasterPass : ScriptableRenderPass
    {
        private static class MainLightShadowConstantBuffer
        {
            public static int _WorldToShadow;
            public static int _ShadowParams;
            public static int _CascadeShadowSplitSpheres0;
            public static int _CascadeShadowSplitSpheres1;
            public static int _CascadeShadowSplitSpheres2;
            public static int _CascadeShadowSplitSpheres3;
            public static int _CascadeShadowSplitSphereRadii;
            public static int _ShadowOffset0;
            public static int _ShadowOffset1;
            public static int _ShadowmapSize;

#if UNITY_GPU_DRIVEN_PIPELINE
            public static int _ShadowDepthParameters;
            public static int _ShadowSource;
            public static int _ResizedShadow;
            public static int[] _MipBatchResults;
#endif
        }

        const int k_MaxCascades = 4;
        const int k_ShadowmapBufferBits = 16;
        float m_CascadeBorder;
        float m_MaxShadowDistanceSq;
        int m_ShadowCasterCascadesCount;

        int m_MainLightShadowmapID;
        internal RTHandle m_MainLightShadowmapTexture;
        private RTHandle m_EmptyMainLightShadowmapTexture;
        private const int k_EmptyShadowMapDimensions = 1;
        private const string k_MainLightShadowMapTextureName = "_MainLightShadowmapTexture";
        private const string k_EmptyMainLightShadowMapTextureName = "_EmptyMainLightShadowmapTexture";
        private static readonly Vector4 s_EmptyShadowParams = new Vector4(1, 0, 1, 0);
        private static readonly Vector4 s_EmptyShadowmapSize = s_EmptyShadowmapSize = new Vector4(k_EmptyShadowMapDimensions, 1f / k_EmptyShadowMapDimensions, k_EmptyShadowMapDimensions, k_EmptyShadowMapDimensions);

        Matrix4x4[] m_MainLightShadowMatrices;
        ShadowSliceData[] m_CascadeSlices;
        Vector4[] m_CascadeSplitDistances;

        bool m_CreateEmptyShadowmap;

        int renderTargetWidth;
        int renderTargetHeight;

        ProfilingSampler m_ProfilingSetupSampler = new ProfilingSampler("Setup Main Shadowmap");

#if UNITY_GPU_DRIVEN_PIPELINE
        internal bool m_EnableGDRP = false;
        private bool m_IsOnlyVGShadow = false;
        private ComputeShader m_DepthPyramidCS;
        private int[] m_ShadowResizeKernels;
        private int[] m_MipBatchKernels;
        // Maybe we need this after Rendering Debugger implements the full screen debug for VG.
        private bool m_DrawShadowGDRP = true;
        private Vector4 m_ShadowDepthParameters;
        // Now, we use a texture with fixed size (256, 256), same with the min resolution of shadowmap.
        private static readonly int s_HizSize = 256;
        private static readonly int s_MaxMipBatchCount = 4;
        // Must be same with the count in ShadowResolution enum.
        private const int k_ShadowResolutionCount = 5;
        private static readonly string[] s_ShadowResizeKernelNames = new string[k_ShadowResolutionCount]
            { "KShadowCopy", "KShadowResize", "KShadowResize", "KShadowResizeBatch8x8", "KShadowResizeBatch16x16" };
        private static readonly Matrix4x4[] s_DefaultHizMatrices = new Matrix4x4[k_MaxCascades];
        private GPUDriven.VGShadowSetting m_ShadowSetting = new GPUDriven.VGShadowSetting();
#endif

        /// <summary>
        /// Creates a new <c>MainLightShadowCasterPass</c> instance.
        /// </summary>
        /// <param name="evt">The <c>RenderPassEvent</c> to use.</param>
        /// <seealso cref="RenderPassEvent"/>
#if UNITY_GPU_DRIVEN_PIPELINE
        public MainLightShadowCasterPass(RenderPassEvent evt, ComputeShader depthPyramidCS)
#else
        public MainLightShadowCasterPass(RenderPassEvent evt)
#endif
        {
            base.profilingSampler = new ProfilingSampler(nameof(MainLightShadowCasterPass));
            renderPassEvent = evt;

            m_MainLightShadowMatrices = new Matrix4x4[k_MaxCascades + 1];
            m_CascadeSlices = new ShadowSliceData[k_MaxCascades];
            m_CascadeSplitDistances = new Vector4[k_MaxCascades];

            MainLightShadowConstantBuffer._WorldToShadow = Shader.PropertyToID("_MainLightWorldToShadow");
            MainLightShadowConstantBuffer._ShadowParams = Shader.PropertyToID("_MainLightShadowParams");
            MainLightShadowConstantBuffer._CascadeShadowSplitSpheres0 = Shader.PropertyToID("_CascadeShadowSplitSpheres0");
            MainLightShadowConstantBuffer._CascadeShadowSplitSpheres1 = Shader.PropertyToID("_CascadeShadowSplitSpheres1");
            MainLightShadowConstantBuffer._CascadeShadowSplitSpheres2 = Shader.PropertyToID("_CascadeShadowSplitSpheres2");
            MainLightShadowConstantBuffer._CascadeShadowSplitSpheres3 = Shader.PropertyToID("_CascadeShadowSplitSpheres3");
            MainLightShadowConstantBuffer._CascadeShadowSplitSphereRadii = Shader.PropertyToID("_CascadeShadowSplitSphereRadii");
            MainLightShadowConstantBuffer._ShadowOffset0 = Shader.PropertyToID("_MainLightShadowOffset0");
            MainLightShadowConstantBuffer._ShadowOffset1 = Shader.PropertyToID("_MainLightShadowOffset1");
            MainLightShadowConstantBuffer._ShadowmapSize = Shader.PropertyToID("_MainLightShadowmapSize");

            m_MainLightShadowmapID = Shader.PropertyToID(k_MainLightShadowMapTextureName);

#if UNITY_GPU_DRIVEN_PIPELINE
            MainLightShadowConstantBuffer._ShadowDepthParameters = Shader.PropertyToID("_ShadowDepthParameters");
            MainLightShadowConstantBuffer._ShadowSource = Shader.PropertyToID("_ShadowSource");
            MainLightShadowConstantBuffer._ResizedShadow = Shader.PropertyToID("_ResizedShadow");
            MainLightShadowConstantBuffer._MipBatchResults = new int[s_MaxMipBatchCount];
            for (int index = 0; index < s_MaxMipBatchCount; ++index)
                MainLightShadowConstantBuffer._MipBatchResults[index] = Shader.PropertyToID("_MipBatchResult" + index.ToString());

            m_ShadowDepthParameters = new Vector4();
            if (depthPyramidCS && depthPyramidCS.GetKernelCount() != 0)
            {
                m_DepthPyramidCS = depthPyramidCS;
                m_ShadowResizeKernels = new int[k_ShadowResolutionCount];
                for (int index = 0; index < k_ShadowResolutionCount; ++index)
                    m_ShadowResizeKernels[index] = m_DepthPyramidCS.FindKernel(s_ShadowResizeKernelNames[index]);
                m_MipBatchKernels = new int[s_MaxMipBatchCount];
                for (int index = 0; index < s_MaxMipBatchCount; ++index)
                    m_MipBatchKernels[index] = m_DepthPyramidCS.FindKernel("Mip_Batch_Pass" + (index + 1).ToString());
            }

            // We just draw main light cascade one by one.
            m_ShadowSetting.shadowViews = new GPUDriven.VGShadowView[k_MaxCascades];
#endif
            m_EmptyMainLightShadowmapTexture = RTHandles.Alloc(Texture2D.blackTexture);
        }

        /// <summary>
        /// Cleans up resources used by the pass.
        /// </summary>
        public void Dispose()
        {
            m_MainLightShadowmapTexture?.Release();
            m_EmptyMainLightShadowmapTexture?.Release();
        }

        /// <summary>
        /// Sets up the pass.
        /// </summary>
        /// <param name="renderingData"></param>
        /// <returns>True if the pass should be enqueued, otherwise false.</returns>
        /// <seealso cref="RenderingData"/>
        public bool Setup(ref RenderingData renderingData)
        {
            if (!renderingData.shadowData.mainLightShadowsEnabled)
                return false;

#if UNITY_EDITOR
            if (CoreUtils.IsSceneLightingDisabled(renderingData.cameraData.camera))
                return false;
#endif

            using var profScope = new ProfilingScope(null, m_ProfilingSetupSampler);

            if (!renderingData.shadowData.supportsMainLightShadows)
                return SetupForEmptyRendering(ref renderingData);

            Clear();
            int shadowLightIndex = renderingData.lightData.mainLightIndex;
            if (shadowLightIndex == -1)
                return SetupForEmptyRendering(ref renderingData);

            VisibleLight shadowLight = renderingData.lightData.visibleLights[shadowLightIndex];
            Light light = shadowLight.light;
            if (light.shadows == LightShadows.None)
                return SetupForEmptyRendering(ref renderingData);

            if (shadowLight.lightType != LightType.Directional)
            {
                Debug.LogWarning("Only directional lights are supported as main light.");
            }

            Bounds bounds;
            if (!renderingData.cullResults.GetShadowCasterBounds(shadowLightIndex, out bounds))
                return SetupForEmptyRendering(ref renderingData);

            m_ShadowCasterCascadesCount = renderingData.shadowData.mainLightShadowCascadesCount;

            int shadowResolution = ShadowUtils.GetMaxTileResolutionInAtlas(renderingData.shadowData.mainLightShadowmapWidth,
                renderingData.shadowData.mainLightShadowmapHeight, m_ShadowCasterCascadesCount);
            renderTargetWidth = renderingData.shadowData.mainLightShadowmapWidth;
            renderTargetHeight = (m_ShadowCasterCascadesCount == 2) ?
                renderingData.shadowData.mainLightShadowmapHeight >> 1 :
                renderingData.shadowData.mainLightShadowmapHeight;

            for (int cascadeIndex = 0; cascadeIndex < m_ShadowCasterCascadesCount; ++cascadeIndex)
            {
                bool success = ShadowUtils.ExtractDirectionalLightMatrix(ref renderingData.cullResults, ref renderingData.shadowData,
                    shadowLightIndex, cascadeIndex, renderTargetWidth, renderTargetHeight, shadowResolution, light.shadowNearPlane,
                    out m_CascadeSplitDistances[cascadeIndex], out m_CascadeSlices[cascadeIndex]);

                if (!success)
                    return SetupForEmptyRendering(ref renderingData);
            }

            m_MaxShadowDistanceSq = renderingData.cameraData.maxShadowDistance * renderingData.cameraData.maxShadowDistance;
            m_CascadeBorder = renderingData.shadowData.mainLightShadowCascadeBorder;
            m_CreateEmptyShadowmap = false;
            useNativeRenderPass = true;
            ShadowUtils.ShadowRTReAllocateIfNeeded(ref m_MainLightShadowmapTexture, renderTargetWidth, renderTargetHeight, k_ShadowmapBufferBits, name: k_MainLightShadowMapTextureName);

#if UNITY_GPU_DRIVEN_PIPELINE
            if (m_EnableGDRP
                && m_DrawShadowGDRP)
            {
                m_IsOnlyVGShadow = bounds.center.Equals(Vector3.zero) && bounds.extents.Equals(Vector3.zero);
                ref var cameraData = ref renderingData.cameraData;
                if (cameraData.vgShadowData != null)
                {
                    ShadowUtils.MainLightShadowHizRTReAllocateIfNeeded(ref cameraData.vgShadowData.hizRT, s_HizSize, s_HizSize, k_ShadowmapBufferBits, k_MainLightShadowMapTextureName + "_HizMap");
                }
                else
                {
#if UNITY_EDITOR
                    // We should add a component holds VG Shadow data for scene camera and preview camera.
                    if (cameraData.camera.cameraType == CameraType.SceneView
                        || cameraData.camera.cameraType == CameraType.Preview)
                    {
                        cameraData.camera.TryGetComponent<VGShadowDataController>(out var vgShadowDataController);
                        if (vgShadowDataController == null)
                            vgShadowDataController = cameraData.camera.gameObject.AddComponent<VGShadowDataController>();
                        ShadowUtils.MainLightShadowHizRTReAllocateIfNeeded(ref vgShadowDataController.hizRT, s_HizSize, s_HizSize, k_ShadowmapBufferBits, k_MainLightShadowMapTextureName + "_HizMap");
                        cameraData.vgShadowData = new VGShadowData();
                        cameraData.vgShadowData.hizRT = vgShadowDataController.hizRT;
                        cameraData.vgShadowData.preViewMatrices = vgShadowDataController.preViewMatrices;
                        cameraData.vgShadowData.preProjMatrices = vgShadowDataController.preProjMatrices;
                    }
#endif
                }
            }
#endif

            return true;
        }

        bool SetupForEmptyRendering(ref RenderingData renderingData)
        {
            if (!renderingData.cameraData.renderer.stripShadowsOffVariants)
                return false;

            m_CreateEmptyShadowmap = true;
            useNativeRenderPass = false;
            ShadowUtils.ShadowRTReAllocateIfNeeded(ref m_EmptyMainLightShadowmapTexture, k_EmptyShadowMapDimensions, k_EmptyShadowMapDimensions, k_ShadowmapBufferBits, name: k_EmptyMainLightShadowMapTextureName);

            return true;
        }

        /// <inheritdoc />
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            
            if (m_CreateEmptyShadowmap)
            {
                // Reset pass RTs to null
                ResetTarget();
                return;
            }
            ConfigureTarget(m_MainLightShadowmapTexture);
            ConfigureClear(ClearFlag.All, Color.black);
        }

        /// <inheritdoc/>
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_CreateEmptyShadowmap)
            {
                SetEmptyMainLightCascadeShadowmap(ref context, ref renderingData);
                renderingData.commandBuffer.SetGlobalTexture(m_MainLightShadowmapID, m_EmptyMainLightShadowmapTexture.nameID);

                return;
            }

            RenderMainLightCascadeShadowmap(ref context, ref renderingData);
            renderingData.commandBuffer.SetGlobalTexture(m_MainLightShadowmapID, m_MainLightShadowmapTexture.nameID);
        }

        void Clear()
        {
            for (int i = 0; i < m_MainLightShadowMatrices.Length; ++i)
                m_MainLightShadowMatrices[i] = Matrix4x4.identity;

            for (int i = 0; i < m_CascadeSplitDistances.Length; ++i)
                m_CascadeSplitDistances[i] = new Vector4(0.0f, 0.0f, 0.0f, 0.0f);

            for (int i = 0; i < m_CascadeSlices.Length; ++i)
                m_CascadeSlices[i].Clear();
            
#if UNITY_GPU_DRIVEN_PIPELINE
            m_IsOnlyVGShadow = false;
#endif
        }

        void SetEmptyMainLightCascadeShadowmap(ref ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = renderingData.commandBuffer;
            CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.MainLightShadows, true);
            SetEmptyMainLightShadowParams(cmd);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
        }

        internal static void SetEmptyMainLightShadowParams(CommandBuffer cmd)
        {
            cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowParams, s_EmptyShadowParams);
            cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowmapSize, s_EmptyShadowmapSize);
        }

#if UNITY_GPU_DRIVEN_PIPELINE
        private void UpdateSrcAndOffset(Vector4[] offsetAndLimits, Vector2Int wholeSize, Vector2Int validSize)
        {
            offsetAndLimits[0].x  = 0;
            offsetAndLimits[0].y  = 0;
            offsetAndLimits[0].z  = validSize.x - 1;
            offsetAndLimits[0].w  = validSize.y - 1;

            offsetAndLimits[1].x  = offsetAndLimits[0].x + wholeSize.x;
            offsetAndLimits[1].y  = offsetAndLimits[0].y;
            offsetAndLimits[1].z  = offsetAndLimits[0].z + wholeSize.x;
            offsetAndLimits[1].w  = offsetAndLimits[0].w;

            offsetAndLimits[2].x  = offsetAndLimits[0].x;
            offsetAndLimits[2].y  = offsetAndLimits[0].y + wholeSize.y;
            offsetAndLimits[2].z  = offsetAndLimits[0].z;
            offsetAndLimits[2].w  = offsetAndLimits[0].w + wholeSize.y;

            offsetAndLimits[3].x  = offsetAndLimits[0].x + wholeSize.x;
            offsetAndLimits[3].y  = offsetAndLimits[0].y + wholeSize.y;
            offsetAndLimits[3].z  = offsetAndLimits[0].z + wholeSize.x;
            offsetAndLimits[3].w  = offsetAndLimits[0].w + wholeSize.y;
        }

        private static int DivRoundUp(int x, int y) => (x + y - 1) / y;

        private void ResizeShadowDepth(CommandBuffer cmd, RTHandle srcRT, RTHandle dstRT)
        {
            var src = srcRT.rt;
            var dst = dstRT.rt;

            var cs = m_DepthPyramidCS;

            // The resolution of shadowmap is always the power of 2, so the unitLength is the same.
            int newWidth = 0, newHeight = 0, unitLength = 0;
            ShadowUtils.CalcResizedRes(src.width, src.height, s_HizSize, s_HizSize, ref newWidth, ref newHeight, ref unitLength);

            int kernelIndex = Mathf.Min(Mathf.RoundToInt(Mathf.Log10(unitLength) / Mathf.Log10(2)), k_ShadowResolutionCount - 1);
            int kernel = m_ShadowResizeKernels[kernelIndex];

            m_ShadowDepthParameters.x = unitLength;
            cmd.SetComputeVectorParam(cs, MainLightShadowConstantBuffer._ShadowDepthParameters, m_ShadowDepthParameters);
            cmd.SetComputeTextureParam(cs, kernel, MainLightShadowConstantBuffer._ShadowSource, src, 0);
            cmd.SetComputeTextureParam(cs, kernel, MainLightShadowConstantBuffer._ResizedShadow, dst, 0);

            Vector2Int dispatchGroup = new Vector2Int(DivRoundUp(dst.width, 8), DivRoundUp(dst.height, 8));
            if (kernelIndex > 2)
            {
                dispatchGroup.x = DivRoundUp(src.width, 8);
                dispatchGroup.y = DivRoundUp(src.height, 8);
            }

            cmd.DispatchCompute(cs, kernel, dispatchGroup.x, dispatchGroup.y, 1);
        }

        private void RenderShadowDepthMipmap(CommandBuffer cmd, RTHandle srcRT)
        {
            var src = srcRT.rt;

            const int mipStartLevel = 1;

            int mipCount = src.mipmapCount;

            // For now, Hiz Cull will gather 4*4, so we cannot access the mip with size (1, 1).
            // So even though the cascade count is more than 1, it is still correct to render
            // mip with size (1, 1), which just costs a little more time.
            for (int startMip = mipStartLevel; startMip < mipCount; startMip += s_MaxMipBatchCount)
            {
                // Get whole dst size.
                Vector2Int dstSize = new Vector2Int(src.width >> startMip, src.height >> startMip);
                int endMip = Mathf.Min(startMip + s_MaxMipBatchCount, mipCount);
                int mipBatchCount = endMip - startMip;
                int kernelSize = (int)Mathf.Pow(2.0f, mipBatchCount - 1);

                var cs = m_DepthPyramidCS;
                int kernel = m_MipBatchKernels[endMip - startMip - 1];

                // Set mip source.
                cmd.SetComputeTextureParam(cs, kernel, MainLightShadowConstantBuffer._ResizedShadow, src, startMip - 1);
                // Set mip result.
                for (int mipResult = startMip; mipResult < endMip; ++mipResult)
                    cmd.SetComputeTextureParam(cs, kernel, MainLightShadowConstantBuffer._MipBatchResults[mipResult - startMip], src, mipResult);

                cmd.DispatchCompute(cs, kernel, DivRoundUp(dstSize.x, kernelSize), DivRoundUp(dstSize.y, kernelSize), 1);
            }
        }
#endif

        void RenderMainLightCascadeShadowmap(ref ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cullResults = renderingData.cullResults;
            var lightData = renderingData.lightData;
            var shadowData = renderingData.shadowData;
#if UNITY_GPU_DRIVEN_PIPELINE
            var vgShadowData = renderingData.cameraData.vgShadowData;
#endif

            int shadowLightIndex = lightData.mainLightIndex;
            if (shadowLightIndex == -1)
                return;

            VisibleLight shadowLight = lightData.visibleLights[shadowLightIndex];

            var cmd = renderingData.commandBuffer;
            using (new ProfilingScope(cmd, ProfilingSampler.Get(URPProfileId.MainLightShadow)))
            {
                // Need to start by setting the Camera position and worldToCamera Matrix as that is not set for passes executed before normal rendering
                ShadowUtils.SetCameraPosition(cmd, renderingData.cameraData.worldSpaceCameraPos);

                // Need set the worldToCamera Matrix as that is not set for passes executed before normal rendering,
                // otherwise shadows will behave incorrectly when Scene and Game windows are open at the same time (UUM-63267).
                ShadowUtils.SetWorldToCameraAndCameraToWorldMatrices(cmd, renderingData.cameraData.GetViewMatrix());

                var settings = new ShadowDrawingSettings(cullResults, shadowLightIndex, BatchCullingProjectionType.Orthographic);
                settings.useRenderingLayerMaskTest = UniversalRenderPipeline.asset.useRenderingLayers;

                for (int cascadeIndex = 0; cascadeIndex < m_ShadowCasterCascadesCount; ++cascadeIndex)
                {
                    settings.splitData = m_CascadeSlices[cascadeIndex].splitData;

                    Vector4 shadowBias = ShadowUtils.GetShadowBias(ref shadowLight, shadowLightIndex, ref renderingData.shadowData, m_CascadeSlices[cascadeIndex].projectionMatrix, m_CascadeSlices[cascadeIndex].resolution);
                    ShadowUtils.SetupShadowCasterConstantBuffer(cmd, ref shadowLight, shadowBias);
                    CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.CastingPunctualLightShadow, false);
#if UNITY_GPU_DRIVEN_PIPELINE
                    // Skip non-VG shadow draw call to save CPU Time.
                    if (!m_EnableGDRP || !m_DrawShadowGDRP || !m_IsOnlyVGShadow)
#endif
                    {
                        ShadowUtils.RenderShadowSlice(cmd, ref context, ref m_CascadeSlices[cascadeIndex],
                            ref settings, m_CascadeSlices[cascadeIndex].projectionMatrix, m_CascadeSlices[cascadeIndex].viewMatrix);
                    }
#if UNITY_GPU_DRIVEN_PIPELINE
                    else
                    {
                        context.ExecuteCommandBuffer(cmd);
                        cmd.Clear();
                    }

                    if (m_EnableGDRP
                        && m_DrawShadowGDRP
                        && vgShadowData != null
                        && vgShadowData.hizRT != null)
                    {
                        var sliceData = m_CascadeSlices[cascadeIndex];

                        m_ShadowSetting.camera = renderingData.cameraData.camera;
                        m_ShadowSetting.enablePostCull = true;
                        m_ShadowSetting.isPostCull = false;
                        m_ShadowSetting.useRenderingLayerMaskTest = UniversalRenderPipeline.asset.useRenderingLayers;
                        m_ShadowSetting.isCameraRelative = false;
                        m_ShadowSetting.shadowmapRT = m_MainLightShadowmapTexture;
                        m_ShadowSetting.hizRT = vgShadowData.hizRT;
                        m_ShadowSetting.viewSizeAndInvSize.Set(renderTargetWidth, renderTargetHeight, 1.0f / renderTargetWidth, 1.0f / renderTargetHeight);

                        var viewport = new Rect(sliceData.offsetX, sliceData.offsetY, sliceData.resolution, sliceData.resolution);
                        var viewportVec = new Vector4(viewport.x, viewport.y, viewport.width, viewport.height);

                        ref var shadowView = ref m_ShadowSetting.shadowViews[cascadeIndex];
                        shadowView.light = shadowLight.light;
                        shadowView.shadowLayerMask = (uint)shadowLight.light.renderingLayerMask;
                        shadowView.lightDirection = -shadowLight.localToWorldMatrix.GetColumn(2);
                        shadowView.lightDirection.w = shadowBias.x;
                        shadowView.lightPosition = shadowLight.localToWorldMatrix.GetColumn(3);
                        shadowView.lightPosition.w = shadowBias.y;
                        shadowView.viewport = viewportVec;
                        shadowView.viewMatrix = sliceData.viewMatrix;
                        shadowView.projMatrix = sliceData.projectionMatrix;
                        shadowView.preViewMatrix = vgShadowData.preViewMatrices[cascadeIndex];
                        shadowView.preProjMatrix = vgShadowData.preProjMatrices[cascadeIndex];
                        if (m_ShadowCasterCascadesCount == 1)
                        {
                            shadowView.depthPyramidSize.Set(s_HizSize, s_HizSize);
                        }
                        else
                        {
                            // If there are more than 1 cascade, each will take one in four of hiz.
                            shadowView.depthPyramidSize.Set(s_HizSize >> 1, s_HizSize >> 1);
                        }
                        shadowView.hizST = viewportVec * s_HizSize / m_MainLightShadowmapTexture.rt.width;

                        vgShadowData.preViewMatrices[cascadeIndex] = sliceData.viewMatrix;
                        vgShadowData.preProjMatrices[cascadeIndex] = sliceData.projectionMatrix;
                    }
#endif
                }

#if UNITY_GPU_DRIVEN_PIPELINE
                if (m_ShadowCasterCascadesCount > 0
                    && m_EnableGDRP
                    && m_DrawShadowGDRP
                    && vgShadowData != null
                    && vgShadowData.hizRT != null)
                {
                    for (int viewIndex = m_ShadowCasterCascadesCount; viewIndex < k_MaxCascades; ++viewIndex)
                    {
                        // Set invalid viewport for the rest.
                        ref var shadowView = ref m_ShadowSetting.shadowViews[viewIndex];
                        shadowView.viewport = Vector4.zero;
                    }
                    GPUDriven.Manager.MainCullVGShadow(cmd, m_ShadowSetting);
                    cmd.SetViewport(new Rect(0, 0, renderTargetWidth, renderTargetHeight));
                    cmd.SetGlobalDepthBias(1.0f, 2.5f);
                    GPUDriven.Manager.RenderVGShadow(cmd, m_ShadowSetting);
                    cmd.SetGlobalDepthBias(0.0f, 0.0f);

                    m_ShadowSetting.isPostCull = true;
                    ResizeShadowDepth(cmd, m_MainLightShadowmapTexture, vgShadowData.hizRT);
                    RenderShadowDepthMipmap(cmd, vgShadowData.hizRT);

                    GPUDriven.Manager.PostCullVGShadow(cmd, m_ShadowSetting);
                    cmd.SetViewport(new Rect(0, 0, renderTargetWidth, renderTargetHeight));
                    cmd.SetGlobalDepthBias(1.0f, 2.5f);
                    GPUDriven.Manager.RenderVGShadow(cmd, m_ShadowSetting);
                    cmd.SetGlobalDepthBias(0.0f, 0.0f);

                    ResizeShadowDepth(cmd, m_MainLightShadowmapTexture, vgShadowData.hizRT);
                    RenderShadowDepthMipmap(cmd, vgShadowData.hizRT);
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                }
#endif

                renderingData.shadowData.isKeywordSoftShadowsEnabled = shadowLight.light.shadows == LightShadows.Soft && renderingData.shadowData.supportsSoftShadows;
                CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.MainLightShadows, renderingData.shadowData.mainLightShadowCascadesCount == 1);
                CoreUtils.SetKeyword(cmd, ShaderKeywordStrings.MainLightShadowCascades, renderingData.shadowData.mainLightShadowCascadesCount > 1);
                ShadowUtils.SetSoftShadowQualityShaderKeywords(cmd, ref renderingData.shadowData);

                SetupMainLightShadowReceiverConstants(cmd, ref shadowLight, ref renderingData.shadowData);
            }
        }

        void SetupMainLightShadowReceiverConstants(CommandBuffer cmd, ref VisibleLight shadowLight, ref ShadowData shadowData)
        {
            Light light = shadowLight.light;
            bool softShadows = shadowLight.light.shadows == LightShadows.Soft && shadowData.supportsSoftShadows;

            int cascadeCount = m_ShadowCasterCascadesCount;
            for (int i = 0; i < cascadeCount; ++i)
                m_MainLightShadowMatrices[i] = m_CascadeSlices[i].shadowTransform;

            // We setup and additional a no-op WorldToShadow matrix in the last index
            // because the ComputeCascadeIndex function in Shadows.hlsl can return an index
            // out of bounds. (position not inside any cascade) and we want to avoid branching
            Matrix4x4 noOpShadowMatrix = Matrix4x4.zero;
            noOpShadowMatrix.m22 = (SystemInfo.usesReversedZBuffer) ? 1.0f : 0.0f;
            for (int i = cascadeCount; i <= k_MaxCascades; ++i)
                m_MainLightShadowMatrices[i] = noOpShadowMatrix;

            float invShadowAtlasWidth = 1.0f / renderTargetWidth;
            float invShadowAtlasHeight = 1.0f / renderTargetHeight;
            float invHalfShadowAtlasWidth = 0.5f * invShadowAtlasWidth;
            float invHalfShadowAtlasHeight = 0.5f * invShadowAtlasHeight;
            float softShadowsProp = ShadowUtils.SoftShadowQualityToShaderProperty(light, softShadows);

            ShadowUtils.GetScaleAndBiasForLinearDistanceFade(m_MaxShadowDistanceSq, m_CascadeBorder, out float shadowFadeScale, out float shadowFadeBias);

            cmd.SetGlobalMatrixArray(MainLightShadowConstantBuffer._WorldToShadow, m_MainLightShadowMatrices);
            cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowParams,
                new Vector4(light.shadowStrength, softShadowsProp, shadowFadeScale, shadowFadeBias));

            if (m_ShadowCasterCascadesCount > 1)
            {
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._CascadeShadowSplitSpheres0,
                    m_CascadeSplitDistances[0]);
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._CascadeShadowSplitSpheres1,
                    m_CascadeSplitDistances[1]);
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._CascadeShadowSplitSpheres2,
                    m_CascadeSplitDistances[2]);
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._CascadeShadowSplitSpheres3,
                    m_CascadeSplitDistances[3]);
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._CascadeShadowSplitSphereRadii, new Vector4(
                    m_CascadeSplitDistances[0].w * m_CascadeSplitDistances[0].w,
                    m_CascadeSplitDistances[1].w * m_CascadeSplitDistances[1].w,
                    m_CascadeSplitDistances[2].w * m_CascadeSplitDistances[2].w,
                    m_CascadeSplitDistances[3].w * m_CascadeSplitDistances[3].w));
            }

            // Inside shader soft shadows are controlled through global keyword.
            // If any additional light has soft shadows it will force soft shadows on main light too.
            // As it is not trivial finding out which additional light has soft shadows, we will pass main light properties if soft shadows are supported.
            // This workaround will be removed once we will support soft shadows per light.
            if (shadowData.supportsSoftShadows)
            {
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowOffset0,
                    new Vector4(-invHalfShadowAtlasWidth, -invHalfShadowAtlasHeight,
                        invHalfShadowAtlasWidth, -invHalfShadowAtlasHeight));
                cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowOffset1,
                    new Vector4(-invHalfShadowAtlasWidth, invHalfShadowAtlasHeight,
                        invHalfShadowAtlasWidth, invHalfShadowAtlasHeight));

                cmd.SetGlobalVector(MainLightShadowConstantBuffer._ShadowmapSize, new Vector4(invShadowAtlasWidth,
                    invShadowAtlasHeight,
                    renderTargetWidth, renderTargetHeight));
            }
        }
        private class PassData
        {
            internal MainLightShadowCasterPass pass;
            internal RenderGraph graph;

            internal TextureHandle shadowmapTexture;
            internal RenderingData renderingData;
            internal int shadowmapID;

            internal bool emptyShadowmap;
        }

        internal TextureHandle Render(RenderGraph graph, ref RenderingData renderingData)
        {
            TextureHandle shadowTexture;

            using (var builder = graph.AddRenderPass<PassData>("Main Light Shadowmap", out var passData, base.profilingSampler))
            {
                InitPassData(ref passData, ref renderingData, ref graph);

                if (!m_CreateEmptyShadowmap)
                {
                    passData.shadowmapTexture = UniversalRenderer.CreateRenderGraphTexture(graph, m_MainLightShadowmapTexture.rt.descriptor, "Main Shadowmap", true, ShadowUtils.m_ForceShadowPointSampling ? FilterMode.Point : FilterMode.Bilinear);
                    builder.UseDepthBuffer(passData.shadowmapTexture, DepthAccess.Write);
                }

                // Need this as shadowmap is only used as Global Texture and not a buffer, so would get culled by RG
                builder.AllowPassCulling(false);

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    if (!data.emptyShadowmap)
                        data.pass.RenderMainLightCascadeShadowmap(ref context.renderContext, ref data.renderingData);
                });

                shadowTexture = passData.shadowmapTexture;
            }

            using (var builder = graph.AddRenderPass<PassData>("Set Main Shadow Globals", out var passData, base.profilingSampler))
            {
                InitPassData(ref passData, ref renderingData, ref graph);

                passData.shadowmapTexture = shadowTexture;

                if (shadowTexture.IsValid())
                    builder.UseDepthBuffer(shadowTexture, DepthAccess.Read);

                builder.AllowPassCulling(false);

                builder.SetRenderFunc((PassData data, RenderGraphContext context) =>
                {
                    if (data.emptyShadowmap)
                    {
                        data.pass.SetEmptyMainLightCascadeShadowmap(ref context.renderContext, ref data.renderingData);
                        data.shadowmapTexture = data.graph.defaultResources.defaultShadowTexture;
                    }

                    data.renderingData.commandBuffer.SetGlobalTexture(data.shadowmapID, data.shadowmapTexture);
                });
                return passData.shadowmapTexture;
            }
        }

        void InitPassData(ref PassData passData, ref RenderingData renderingData, ref RenderGraph graph)
        {
            passData.pass = this;
            passData.graph = graph;

            passData.emptyShadowmap = m_CreateEmptyShadowmap;
            passData.shadowmapID = m_MainLightShadowmapID;
            passData.renderingData = renderingData;
        }
    };
}
