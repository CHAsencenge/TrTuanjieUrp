using System;
using UnityEngine.Experimental.Rendering;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// TJSR history data that persists over a frame. (per camera)
    /// Adapt for XR multi-pass with two views.
    /// </summary>
    sealed internal class TjsrPersistentData : ITemporalPersistentHistory
    {
        TJSR.TjsrHistoryData[] m_historyData = new TJSR.TjsrHistoryData[2];

        internal TjsrPersistentData(bool xrMultipassEnabled)
        {
            int eyeCnt = xrMultipassEnabled ? 2 : 1;
            for (int eyeIndex = 0; eyeIndex < eyeCnt; ++eyeIndex)
            {
                m_historyData[eyeIndex] = new TJSR.TjsrHistoryData();
            }
        }

        internal TJSR.TjsrHistoryData GetHistoryData(int eyeIndex)
        {
            // TJSR only supports XR multi-pass with two views
            Debug.Assert(eyeIndex < 2);

            return m_historyData[eyeIndex];
        }

        public void UpdateTargets(ref CameraData cameraData)
        {
            bool xrMultipassEnabled = false;
#if ENABLE_VR && ENABLE_XR_MODULE
            xrMultipassEnabled = cameraData.xr.enabled && !cameraData.xr.singlePassEnabled;
#endif
            int eyeIndex = xrMultipassEnabled ? Mathf.Clamp(cameraData.xr.multipassId, 0, 1) : 0;
            var currentHistoryData = m_historyData[eyeIndex];
            if (currentHistoryData == null)
            {
                Debug.LogError("[TJSR] Invalid history data of eye index: " + eyeIndex);
                return;
            }

            bool useLumaHistory = false;
            // If useLumaHistory is false, LumaHistory would not be allocated,
            // and config.enableIntermediateColor would be set to false.
            // Here useLumaHistory had better be the same as enableYCoCgColor keyword according to quality level.
            switch (UniversalRenderPipeline.asset.tjsrSettings.tjsrQuality)
            {
                case TJSRQuality.High:
                    useLumaHistory = true;
                    break;
                case TJSRQuality.Medium:
                    useLumaHistory = true;
                    break;
                case TJSRQuality.Low:
                    useLumaHistory = false;
                    break;
            }

            TJSR.TjsrHistoryData.HistoryUpdateInfo info;
            info.preUpscaleSize = new Vector2Int(cameraData.cameraTargetDescriptor.width, cameraData.cameraTargetDescriptor.height);
            info.postUpscaleSize = new Vector2Int(cameraData.pixelWidth, cameraData.pixelHeight);
            info.useHwDrs = false;
            info.useTexArray = cameraData.xr.enabled && cameraData.xr.singlePassEnabled;
            info.useLumaHistory = useLumaHistory;
            info.graphicsFormat = (int)cameraData.cameraTargetDescriptor.graphicsFormat;

            var hash = TJSR.TjsrHistoryData.ComputeHistoryHash(ref info);
            bool hasValidHistory = (hash == currentHistoryData.m_hash);
            if (!hasValidHistory)
            {
                currentHistoryData.Dispose();

                var desc = cameraData.cameraTargetDescriptor;
                {
                    var outDesc = desc;
                    outDesc.width = cameraData.pixelWidth;
                    outDesc.height = cameraData.pixelHeight;
                    outDesc.depthBufferBits = (int)DepthBits.None;
                    outDesc.msaaSamples = (int)MSAASamples.None;
                    // It's a workaround to fix spots effects in some MTK devices when HDR is on.
                    // Replace B10G11R11_UFloatPack32 with 64-bit HDR format for Feedback Texture.
                    if (outDesc.graphicsFormat == GraphicsFormat.B10G11R11_UFloatPack32 && SystemInfo.graphicsDeviceName.StartsWith("Mali"))
                    {
                        outDesc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
                    }
                    currentHistoryData.m_tjsrPriorFeedback = RTHandles.Alloc(outDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrPriorFeedback);
                }

                if (useLumaHistory)
                {
                    if (RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.R8G8_UNorm, FormatUsage.Render))
                    {
                        var tjsrRtDesc = desc;
                        tjsrRtDesc.graphicsFormat = GraphicsFormat.R8G8_UNorm;
                        tjsrRtDesc.msaaSamples = (int)MSAASamples.None;
                        tjsrRtDesc.depthBufferBits = (int)DepthBits.None;
                        tjsrRtDesc.width = cameraData.cameraTargetDescriptor.width;
                        tjsrRtDesc.height = cameraData.cameraTargetDescriptor.height;
                        tjsrRtDesc.sRGB = false;
                        tjsrRtDesc.useDynamicScale = false;
                        tjsrRtDesc.volumeDepth = info.useTexArray ? TextureXR.slices : 1;
                        tjsrRtDesc.dimension = info.useTexArray ? TextureXR.dimension : TextureDimension.Tex2D;
                        currentHistoryData.m_tjsrLumaHistory = RTHandles.Alloc(tjsrRtDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrLumaHistory + "A");
                        currentHistoryData.m_tjsrPrevLumaHistory = RTHandles.Alloc(tjsrRtDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrLumaHistory + "B");
                    }
                    else
                    {
                        Debug.LogError("[TJSR] LumaHistory buffer failed to allocate because the device cannot support R8G8_UNorm format in quality " + UniversalRenderPipeline.asset.tjsrSettings.tjsrQuality + " !");
                    }
                }

                currentHistoryData.m_hash = hash;
            }

            // Fill new history with current frame
            // XR Multipass renders a "frame" per eye
            if (!hasValidHistory)
                cameraData.taaSettings.resetHistoryFrames += xrMultipassEnabled ? 2 : 1;
        }

        public void DeallocateTargets()
        {
            for (int i = 0; i < 2; i++)
            {
                m_historyData[i]?.Dispose();
            }
        }

    }

    public static class TjsrUtils
    {
        /// <summary>
        /// Acquire the graphics format for the intermediate color texture.
        /// </summary>
        static GraphicsFormat MakeIntermediateColorGraphicsFormat(bool isHdrEnabled, HDRColorBufferPrecision requestHDRColorBufferPrecision, bool needsAlpha)
        {
            if (isHdrEnabled)
            {
                //if (needsAlpha && requestHDRColorBufferPrecision == HDRColorBufferPrecision._64Bits)
                {
                    if (RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.R16G16B16A16_SFloat, FormatUsage.Linear | FormatUsage.Render))
                        return GraphicsFormat.R16G16B16A16_SFloat;

                    Debug.LogWarning("[TJSR] The device cannot support R16G16B16A16_SFloat format, fallback to LDR format. Note to lose color precision in HDR mode!");
                }
                // TJU6URP-70: IntermediateColor using B10G11R11_UFloatPack32 format would make color dark, so replace it with R16G16B16A16_SFloat format temporarily in HDR mode. 
                //else
                //{
                //    if (RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.B10G11R11_UFloatPack32, FormatUsage.Linear | FormatUsage.Render))
                //        return GraphicsFormat.B10G11R11_UFloatPack32;

                //    if (isHdrEnabled)
                //        Debug.LogWarning("[TJSR] The device cannot support B10G11R11_UFloatPack32 format, fallback to LDR format. Note to lose color precision in HDR mode!");
                //}
            }

            // Intermediate Color buffer need alpha channel for PostProcess Preserve Alpha feature.
            if (!needsAlpha)
            {
                if (RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.A2B10G10R10_UNormPack32, FormatUsage.Linear | FormatUsage.Render))
                    return GraphicsFormat.A2B10G10R10_UNormPack32;
            }

            return GraphicsFormat.R8G8B8A8_UNorm;
        }

        /// <summary>
        /// Update the allocation of the intermediate render targets and Shader keywords.
        /// </summary>
        static void UpdateShaderResources(ref CameraData cameraData, ref TJSR.TjsrRenderState renderState, ref Material tjsrMaterial)
        {
            var desc = cameraData.cameraTargetDescriptor;

            var tjsrRtDesc = desc;
            tjsrRtDesc.depthBufferBits = (int)DepthBits.None;
            tjsrRtDesc.width = renderState.config.inputImageSize.x;
            tjsrRtDesc.height = renderState.config.inputImageSize.y;
            tjsrRtDesc.sRGB = false;
            tjsrRtDesc.useDynamicScale = false;

            //Reconstruct Pass in Medium or Low quality level choose to pack DepthMotion buffer into UINT format.
            bool packDepthMotion = !renderState.config.enableActivePass;
            // UINT texture sampler is not supported in GLES2.
            packDepthMotion &= SystemInfo.graphicsDeviceType != GraphicsDeviceType.OpenGLES2;
            if (packDepthMotion)
            {
                tjsrRtDesc.graphicsFormat = GraphicsFormat.R32_UInt;
                // No need to define Keyword TJSR_PACK_DEPTH_MOTION, because it depends on !TJSR_HAS_ACTIVE_PASS
                //tjsrMaterial.EnableKeyword(TJSR.ShaderKeywords.TJSR_PACK_DEPTH_MOTION);
                RenderingUtils.ReAllocateIfNeeded(ref renderState.intermediateRTs.tjsrMotionDepthBuffer, tjsrRtDesc, FilterMode.Point, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrMotionDepthBuffer);
            }
            else
            {
                if (RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.R16G16B16A16_SNorm, FormatUsage.Linear | FormatUsage.Render))
                    tjsrRtDesc.graphicsFormat = GraphicsFormat.R16G16B16A16_SNorm;
                else
                    tjsrRtDesc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;

                //tjsrMaterial.DisableKeyword(TJSR.ShaderKeywords.TJSR_PACK_DEPTH_MOTION);
                RenderingUtils.ReAllocateIfNeeded(ref renderState.intermediateRTs.tjsrMotionDepthBuffer, tjsrRtDesc, FilterMode.Point, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrMotionDepthBuffer);
            }

            if (renderState.config.enableIntermediateColor)
            {
                FilterMode filterMode = FilterMode.Bilinear;
                // Disable UINT format intermediate color to save shader variants in the runtime.
                //tjsrMaterial.EnableKeyword(TJSR.ShaderKeywords.TJSR_UINT_INTERMEDIATE);
                //tjsrRtDesc.graphicsFormat = GraphicsFormat.R32_UInt;
                tjsrMaterial.DisableKeyword(TJSR.ShaderKeywords.TJSR_UINT_INTERMEDIATE);
                tjsrRtDesc.graphicsFormat = MakeIntermediateColorGraphicsFormat(cameraData.isHdrEnabled, cameraData.hdrColorBufferPrecision, cameraData.preserveAlpha);
                
                RenderingUtils.ReAllocateIfNeeded(ref renderState.intermediateRTs.tjsrIntermediateColor, tjsrRtDesc, filterMode, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrIntermediateColor);
                tjsrMaterial.EnableKeyword(TJSR.ShaderKeywords.TJSR_INTERMEDIATE_COLOR);
            }
            else
            {
                renderState.intermediateRTs.tjsrIntermediateColor?.Release();
                tjsrMaterial.DisableKeyword(TJSR.ShaderKeywords.TJSR_INTERMEDIATE_COLOR);
            }

            if (renderState.config.enableActivePass)
            {
                tjsrRtDesc.msaaSamples = (int)MSAASamples.None;
                tjsrRtDesc.graphicsFormat = GraphicsFormat.R8_UNorm;

                RenderingUtils.ReAllocateIfNeeded(ref renderState.intermediateRTs.tjsrDepthClip, tjsrRtDesc, FilterMode.Point, TextureWrapMode.Clamp, name: TJSR.ShaderResources.k_TjsrDepthClip);
            }

            CoreUtils.SetKeyword(tjsrMaterial, ShaderKeywordStrings._PRESERVE_ALPHA, cameraData.preserveAlpha);

            #region DEBUG
            renderState.debugViewIndex = TJSR.DebugViewType.Undefined;
            DebugHandler debugHandler = ScriptableRenderPass.GetActiveDebugHandler(ref cameraData);
            if ((debugHandler != null) && debugHandler.TryGetFullscreenDebugMode(out var fullscreenDebugMode))
            {
                if (fullscreenDebugMode == DebugFullScreenMode.TJSR)
                {
                    // debugHandler.tjsrDebugViewIndex is the index value of dropdown in Rendering Debugger,
                    // and it needs to be added by 1 to correspond to the TJSR.DebugViewType value.
                    if (!Enum.IsDefined(typeof(TJSR.DebugViewType), debugHandler.tjsrDebugViewIndex + 1))
                    {
                        Debug.LogError("[TJSR] Invalid debug view index!");
                        return;
                    }
                    renderState.debugViewIndex = (TJSR.DebugViewType)(debugHandler.tjsrDebugViewIndex + 1);

                    if (renderState.debugViewIndex == TJSR.DebugViewType.HistoryWeight)
                    {
                        tjsrMaterial.EnableKeyword(TJSR.ShaderKeywords.TJSR_DEBUGVIEW);
                    }
                    else
                    {
                        tjsrMaterial.DisableKeyword(TJSR.ShaderKeywords.TJSR_DEBUGVIEW);
                    }

                    var debugDesc = tjsrRtDesc;
                    debugDesc.msaaSamples = (int)MSAASamples.None;
                    debugDesc.graphicsFormat = GraphicsFormat.R8G8B8A8_UNorm;
                    if (renderState.debugViewIndex == TJSR.DebugViewType.HistoryWeight)
                    {
                        debugDesc.width = renderState.config.outputImageSize.x;
                        debugDesc.height = renderState.config.outputImageSize.y;
                    }
                    else
                    {
                        debugDesc.width = renderState.config.inputImageSize.x;
                        debugDesc.height = renderState.config.inputImageSize.y;
                    }
                    RenderingUtils.ReAllocateIfNeeded(ref renderState.intermediateRTs.tjsrDebugView, debugDesc, FilterMode.Bilinear, TextureWrapMode.Repeat, name: TJSR.ShaderResources.k_TjsrDebugView);
                }
                else
                {
                    tjsrMaterial.DisableKeyword(TJSR.ShaderKeywords.TJSR_DEBUGVIEW);
                }
            }
            #endregion
        }

        /// <summary>
        /// Populate configuration and material data from camera data.
        /// </summary>
        static bool PopulateTjsrConfig(ref CameraData cameraData, ref TJSR.TjsrRenderState renderState, out TJSR.MaterialData materialData)
        {
            renderState.config.inputImageSize = new Vector2Int(cameraData.cameraTargetDescriptor.width, cameraData.cameraTargetDescriptor.height);
            renderState.config.outputImageSize = new Vector2Int(cameraData.pixelWidth, cameraData.pixelHeight);

            renderState.hasValidHistory = !cameraData.resetHistory;
            renderState.frameIndex = TemporalUtils.CalculateTaaFrameIndex(ref cameraData.taaSettings);

            // Config TJSR parameters according to the quality level
            switch (UniversalRenderPipeline.asset.tjsrSettings.tjsrQuality)
            {
                case TJSRQuality.High:
                    renderState.config.enableActivePass = true;
                    break;
                case TJSRQuality.Medium:
                    renderState.config.enableActivePass = false;
                    break;
                case TJSRQuality.Low:
                    renderState.config.enableActivePass = false;
                    break;
            }

            // Set material data
            materialData._sourceSize = new(1f / renderState.config.inputImageSize.x, 1f / renderState.config.inputImageSize.y, renderState.config.inputImageSize.x, renderState.config.inputImageSize.y);
            float jitterScale = 1.0f;// TJSR also uses cameraData.taaSettings.jitterScale?
            materialData._jitterOffset = TemporalUtils.CalculateJitter(renderState.frameIndex) * jitterScale;
            materialData._cameraFovAngleHor = cameraData.camera.fieldOfView * Mathf.Deg2Rad;
            // Combine the valid history reset and the frame influence blend factor into one parameter.
            materialData._blendFactor = renderState.hasValidHistory ? UniversalRenderPipeline.asset.tjsrSettings.tjsrBaseBlendFactor * 0.5f : 1.0f;
            // [debugViewIndex | qualityLevel]
            int debugViewIndex = (int)renderState.debugViewIndex;
            materialData._qualityLevel = (int)UniversalRenderPipeline.asset.tjsrSettings.tjsrQuality;
            materialData._qualityLevel |= (debugViewIndex & 0xFF) << 8;

            // Validate history data
            TjsrPersistentData tjsrPersistentData = cameraData.temporalPersistentData as TjsrPersistentData;
            Debug.Assert(tjsrPersistentData != null);
            int eyeIndex = (cameraData.xr.enabled && !cameraData.xr.singlePassEnabled) ? cameraData.xr.multipassId : 0;
            materialData.historyData = tjsrPersistentData.GetHistoryData(eyeIndex);
            if (materialData.historyData == null || !materialData.historyData.HasValidHistory())
            {
                Debug.LogError("[TJSR] Invalid history data of eye index: " + eyeIndex);
                return false;
            }

            renderState.config.enableIntermediateColor = (materialData.historyData.m_tjsrLumaHistory != null && materialData.historyData.m_tjsrPrevLumaHistory != null);
            Debug.Assert(renderState.config.enableIntermediateColor || !renderState.config.enableActivePass, "[TJSR] The 3-pass fragment shader in High quality level must be with Intermediate Color feature enabled.");

            return true;
        }

        /// <summary>
        /// Execute the render graph of Tuanjie Super Resolution.
        /// </summary>
        public static void ExecutePass(CommandBuffer cmd, Material tjsrMaterial, ref CameraData cameraData, RTHandle source, RTHandle destination, RenderTexture motionVectors, ref TJSR.TjsrRenderState renderState)
        {
            if (!PopulateTjsrConfig(ref cameraData, ref renderState, out TJSR.MaterialData passData))
                return;
            UpdateShaderResources(ref cameraData, ref renderState, ref tjsrMaterial);
            TJSR.Execute(cmd, source, destination, motionVectors, ref renderState, ref tjsrMaterial, ref passData);
        }
    }
}
