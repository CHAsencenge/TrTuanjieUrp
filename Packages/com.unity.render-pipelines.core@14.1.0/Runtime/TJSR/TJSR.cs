using System;

namespace UnityEngine.Rendering
{
    /// <summary>
    /// Interface to the Tuanjie Super Resolution (TJSR) Post-Processing Upscaler.
    /// It's a temporal upscaling solution used as a TAA(Temporal Anti-Aliasing) override for Tuanjie URP and HDRP renderer.
    /// Its main goal is to improve the quality of the final image by reducing aliasing, flicker and ghosting while increasing image resolution.
    /// The limitation is not perfect for diagonal edge handling and the rotate objects, especially for missing valid motion vector.
    /// In Low quality level, the performance and power consumption are cited as a primary consideration, and optimal for low-end mobile devices.
    /// In Medium quality level, ensuring applications retain their visual fidelity while has the good balance between performance and visual quality for mobile and VR/XR applications.
    /// In High quality level, has more fragment passes and GPU bandwidth than Low/Medium quality level, and recommended for Desktop/Console and higher-end Mobile applications.
    /// </summary>
    public static class TJSR
    {
        /// <summary>
        /// Top-level configuration structure required for TJSR execution
        /// </summary>
        public struct Config
        {
            /// <summary>
            /// Size of the current viewport in pixels
            /// Used to calculate image coordinate scaling factors
            /// </summary>
            public Vector2Int inputImageSize;

            /// <summary>
            /// Size of the upscaled output image in pixels
            /// Used to calculate image coordinate scaling factors
            /// </summary>
            public Vector2Int outputImageSize;

            /// <summary>
            /// The option to enable additional Active pass
            /// to compute depth clip and luminance difference from dilated Motion buffer and dilated Depth buffer.
            /// </summary>
            public bool enableActivePass;

            /// <summary>
            /// The option to allocate Intermediate Color Buffer
            /// and to swap two Luma History Buffers.
            /// Intermediate Color Buffer could convert input Color Buffer into YCoCg color space to blend color value.
            /// Luma History Buffers could store the luminance difference between the current frame and the previous frame.
            /// </summary>
            public bool enableIntermediateColor;
        }

        /// <summary>
        /// Intermediate Render Targets required by TJSR's implementation
        /// </summary>
        public sealed class TjsrIntermediateRT : IDisposable
        {
            /// <summary>
            /// Motion Depth texture to store dilated Motion buffer and dilated Depth buffer.
            /// </summary>
            public RTHandle tjsrMotionDepthBuffer;

            /// <summary>
            /// Intermediate Color texture which is used to convert input Color buffer into YCoCg color space.
            /// </summary>
            public RTHandle tjsrIntermediateColor;

            /// <summary>
            /// Depth Clip texture which is used to generate disocclusion map from dilated Motion buffer and dilated Depth buffer.
            /// </summary>
            public RTHandle tjsrDepthClip;

            /// <summary>
            /// [Optional] Output debug view texture which TJSR can be configured to render debug visualizations into
            /// </summary>
            public RTHandle tjsrDebugView;

            public void Dispose()
            {
                tjsrMotionDepthBuffer?.Release();
                tjsrDepthClip?.Release();
                tjsrIntermediateColor?.Release();
                tjsrDebugView?.Release();
            }
        }

        /// <summary>
        /// The rendering state cache required for TJSR execution
        /// </summary>
        public sealed class TjsrRenderState
        {
            /// <summary>
            /// Top-level configuration structure required for TJSR execution
            /// </summary>
            public Config config;

            /// <summary>
            /// Intermediate Render Targets to use when executing TJSR
            /// </summary>
            public TjsrIntermediateRT intermediateRTs;

            /// <summary>
            /// Index of the current frame
            /// Used to calculate jitter pattern
            /// </summary>
            public int frameIndex;

            /// <summary>
            /// True if the current frame has valid history information
            /// Used to prevent TJSR from producing invalid data
            /// Invalid history means a large degree of temporal consistency between any two consecutive frames.
            /// For example, in order to indicate that a jump cut has occurred with the camera
            /// you should set the hasValidHistory field to false for the first frame of the discontinuous camera transformation.
            /// </summary>
            public bool hasValidHistory;

            /// <summary>
            /// An index value that indicates which debug visualization to render in the debug view
            /// This value is only used when a valid debug view handle is provided
            /// </summary>
            public DebugViewType debugViewIndex;

            /// <summary>
            /// The cached shader pass state resources to use when executing TJSR.
            /// Shader pass index has to be inquired by name because shader stripper would reorder the pass index.
            /// Shader pass render target identifiers has to be cached to resolve GC.Alloc during rendering.
            /// </summary>
            public ShaderPassResources shaderPass;

            public TjsrRenderState()
            {
                intermediateRTs = new();
                shaderPass = new();
            }
        }

        /// <summary>
        /// Shader resource ids used to communicate with the TJSR shader implementation
        /// </summary>
        public static class ShaderResources
        {
            public const string k_TjsrMotionVectorTex = "_TjsrMotionVectorTex";
            public const string k_TjsrMotionDepthBuffer = "_TjsrMotionDepthBuffer";
            public const string k_TjsrIntermediateColor = "_TjsrIntermediateColor";
            public const string k_TjsrLumaHistory = "_TjsrLumaHistory";
            public const string k_TjsrDepthClip = "_TjsrDepthClip";
            public const string k_TjsrPriorFeedback = "_TjsrPriorFeedback";
            public const string k_TjsrDebugView = "TJSR Debug View";

            public static readonly int _sourceSize = Shader.PropertyToID("_SourceSize");
            public static readonly int _jitterOffset = Shader.PropertyToID("_jitterOffset");
            public static readonly int _cameraFovAngleHor = Shader.PropertyToID("_cameraFovAngleHor");
            public static readonly int _blendFactor = Shader.PropertyToID("_blendFactor");
            public static readonly int _qualityLevel = Shader.PropertyToID("_qualityLevel");

            public static readonly int _TjsrMotionVectorTex = Shader.PropertyToID(k_TjsrMotionVectorTex);
            public static readonly int _TjsrMotionDepthBuffer = Shader.PropertyToID(k_TjsrMotionDepthBuffer);
            public static readonly int _TjsrIntermediateColor = Shader.PropertyToID(k_TjsrIntermediateColor);
            public static readonly int _TjsrLumaHistory = Shader.PropertyToID(k_TjsrLumaHistory);
            public static readonly int _TjsrDepthClip = Shader.PropertyToID(k_TjsrDepthClip);
            public static readonly int _TjsrPriorFeedback = Shader.PropertyToID(k_TjsrPriorFeedback);
        }

        /// <summary>
        /// TJSR shader pass state resources including pass index and render target identifiers for each pass.
        /// </summary>
        public class ShaderPassResources
        {
            public enum PassId
            {
                TjsrUpscale = 0,
                TjsrSetup,
                TjsrActive,
                TjsrReconstruct,
                TjsrDebug
            }

            // Shader pass index has to be inquired by its name in the runtime because shader stripper would reorder the pass index.
            public static readonly string kPassNameTJSRSetup = "TJSR - Setup";
            public static readonly string kPassNameTJSRActive = "TJSR - Active";
            public static readonly string kPassNameTJSRReconstruct = "TJSR - Reconstruct";
            public static readonly string kPassNameTJSRDebugView = "TJSR - Debug";

            internal int idTJSRSetup = -1;
            internal int idTJSRActive = -1;
            internal int idTJSRReconstruct = -1;
            internal int idTJSRDebugView = -1;

            // Multiple render target identifiers for each pass of TJSR.
            internal RenderTargetIdentifier[] mrtSetup;
            internal RenderTargetIdentifier[] mrtActive;
            internal RenderTargetIdentifier[] mrtRecon;
            internal RenderTargetIdentifier[] mrtUpscale;

            public ShaderPassResources()
            {
                // TJSR need to initialize MultipleRenderTarget identifiers here to avoid GC.Alloc during rendering.
                // Allocate the maximum array length that TJSR may use, although in some cases these arrays may not be used.
                mrtSetup = new RenderTargetIdentifier[2];
                mrtActive = new RenderTargetIdentifier[2];
                mrtRecon = new RenderTargetIdentifier[3];
                mrtUpscale = new RenderTargetIdentifier[2];
            }
        }

        /// <summary>
        /// Shader keyword strings used to configure the TJSR shader implementation
        /// </summary>
        public static class ShaderKeywords
        {
            public static readonly string TJSR_HAS_ACTIVE_PASS = "_TJSR_HAS_ACTIVE_PASS";
            public static readonly string TJSR_INTERMEDIATE_COLOR = "_TJSR_INTERMEDIATE_COLOR";
            public static readonly string TJSR_UINT_INTERMEDIATE = "_TJSR_UINT_INTERMEDIATE";
            public static readonly string TJSR_DEBUGVIEW = "_TJSR_DEBUGVIEW";
        }

        /// <summary>
        /// Persistent history information required by TJSR's implementation
        /// Users are expected to create their own persistent history data, update it once per frame, and provide it to
        /// TJSR's execution logic through the configuration structure.
        /// </summary>
        public sealed class TjsrHistoryData : IDisposable
        {
            /// <summary>
            /// The frame index to check if the new frame need to be updated.
            /// </summary>
            public int m_lastUpdateFrameIndex;

            /// <summary>
            /// Luma History texture to store luminance buffer for the history swap.
            /// </summary>
            public RTHandle m_tjsrLumaHistory;

            /// <summary>
            /// Luma History texture to store luminance buffer for the history swap.
            /// </summary>
            public RTHandle m_tjsrPrevLumaHistory;

            /// <summary>
            /// Prior Feedback texture to store color buffer of the previous frame for the history swap.
            /// </summary>
            public RTHandle m_tjsrPriorFeedback;

            /// <summary>
            /// Hash value that changes whenever the history data needs to be re-created
            /// </summary>
            public Hash128 m_hash;

            /// <summary>
            /// Describes the information needed to update the history data
            /// </summary>
            public struct HistoryUpdateInfo
            {
                /// <summary>
                /// Size of the target image before upscaling is applied
                /// </summary>
                public Vector2Int preUpscaleSize;

                /// <summary>
                /// Size of the target image after upscaling is applied
                /// </summary>
                public Vector2Int postUpscaleSize;

                /// <summary>
                /// True if hardware dynamic resolution scaling is active
                /// </summary>
                public bool useHwDrs;

                /// <summary>
                /// True if texture arrays are being used in the current rendering environment
                /// </summary>
                public bool useTexArray;

                /// <summary>
                /// True if the swap luminance history buffers need to be allocated
                /// </summary>
                public bool useLumaHistory;

                /// <summary>
                /// GraphicsFormat of the render target.
                /// It will be changed when turn on/off Rendering Debugger and HDR.
                /// </summary>
                public int graphicsFormat;
            }

            /// <summary>
            /// Computes a hash value that changes whenever the history data needs to be re-created
            /// </summary>
            /// <param name="info">update information used to calculate the history hash</param>
            /// <returns>A hash value that changes whenever the history data needs to be re-created</returns>
            public static Hash128 ComputeHistoryHash(ref HistoryUpdateInfo info)
            {
                Hash128 hash = new Hash128();

                hash.Append(ref info.useHwDrs);
                hash.Append(ref info.useTexArray);
                hash.Append(ref info.useLumaHistory);
                hash.Append(ref info.postUpscaleSize);
                hash.Append(ref info.graphicsFormat);

                // The pre-upscale size only affects the history texture logic when hardware dynamic resolution scaling is disabled.
                if (!info.useHwDrs)
                {
                    hash.Append(ref info.preUpscaleSize);
                }

                return hash;
            }

            /// <summary>
            /// Swap the history buffer when the new frame is updated.
            /// </summary>
            public void SwapHistory()
            {
                (m_tjsrLumaHistory, m_tjsrPrevLumaHistory) = (m_tjsrPrevLumaHistory, m_tjsrLumaHistory);
            }

            /// <summary>
            /// Check if this history data is valid.
            /// </summary>
            /// <returns>True if this history data has a valid feedback.</returns>
            public bool HasValidHistory()
            {
                return (m_tjsrPriorFeedback != null);
            }

            public void Dispose()
            {
                m_tjsrLumaHistory?.Release();
                m_tjsrPrevLumaHistory?.Release();
                m_tjsrPriorFeedback?.Release();

                m_tjsrLumaHistory = null;
                m_tjsrPrevLumaHistory = null;
                m_tjsrPriorFeedback = null;

                m_hash = Hash128.Compute(0);
                m_lastUpdateFrameIndex = -1;
            }
        }

        #region DebugView
        // We use a constant to define the debug view arrays to guarantee that they're exactly the same length at compile time
        const int kNumDebugViews = 4;

        // We define a fixed array of GUIContent values here which map to supported debug views within the TJSR shader code
        static readonly GUIContent[] s_DebugViewDescriptions = new GUIContent[kNumDebugViews]
        {
            new GUIContent("Luminance", "Shows luminance value from input color buffer (disabled in Low quality level)"),
            new GUIContent("Disocclusion mask", "Shows disocclusion edges with scale {0 to 1} based on current depth and reprojected previous depth"),
            new GUIContent("Shading change", "Shows luminance changed (0: no change or 1: changed) from the previous frame (disabled in Low quality level)"),
            new GUIContent("History weight", "Shows accumulate blend weight between the history color and the resolved color in phase Upscale Pass"),
        };

        // Unfortunately we must maintain a sequence of index values that map to the supported debug view indices
        // if we want to be able to display the debug views as an enum field without allocating any garbage.
        static readonly int[] s_DebugViewIndices = new int[kNumDebugViews]
        {
            0,
            1,
            2,
            3,
        };

        /// <summary>
        /// Enumeration of unique types of debug render view textures
        /// </summary>
        public enum DebugViewType
        {
            Undefined = 0,
            Luminance,
            DisocclusionMask,
            ShadingChange,
            HistoryWeight,
        }

        /// <summary>
        /// Array of debug view descriptions expected to be used in the rendering debugger UI
        /// </summary>
        public static GUIContent[] debugViewDescriptions { get { return s_DebugViewDescriptions; } }

        /// <summary>
        /// Array of debug view indices expected to be used in the rendering debugger UI
        /// </summary>
        public static int[] debugViewIndices { get { return s_DebugViewIndices; } }
        #endregion //DebugView

        /// <summary>
        /// Material data copied from TJSR shader implementation
        /// </summary>
        public struct MaterialData
        {
            public Vector4 _sourceSize;      // Render size (1/w, 1/h, w, h)
            public Vector2 _jitterOffset;    // Ranges from [-0.5, 0.5], calculated using the Halton sequence
            public float _cameraFovAngleHor; // Horizontal camera FOV
            public float _blendFactor;       // To blend history color value with the accumulate value if this blend factor is 0. If the camera view is discontinuous or the scene is switching, the accumulation should be reset, then set this blend factor to greater than one to force to use accumulate color value from the current frame.
            public int _qualityLevel;        // Quality level from settings to choose 9 taps or 5 taps filter.

            /// <summary>
            /// Persistent history data to use when executing TJSR
            /// </summary>
            public TjsrHistoryData historyData;
        }

        static void SetMaterialData(ref Material tjsrMaterial, ref MaterialData data)
        {
            tjsrMaterial.SetVector(ShaderResources._sourceSize, data._sourceSize);
            tjsrMaterial.SetVector(ShaderResources._jitterOffset, data._jitterOffset);
            tjsrMaterial.SetFloat(ShaderResources._cameraFovAngleHor, data._cameraFovAngleHor);
            tjsrMaterial.SetFloat(ShaderResources._blendFactor, data._blendFactor);
            tjsrMaterial.SetFloat(ShaderResources._qualityLevel, (float)data._qualityLevel);
        }

        /// <summary>
        /// Executes the TJSR technique using the provided configuration in the target render graph
        /// </summary>
        /// <param name="cmd">command buffer to execute TJSR within</param>
        /// <param name="source">Texture handle that contains the rendered color input</param>
        /// <param name="destination">Texture handle that contains the upscaled color output</param>
        /// <param name="motionVectors">Texture handle that contains the motione vector input</param>
        /// <param name="state">The rendering state cache including configuration parameters for TJSR</param>
        public static void Execute(CommandBuffer cmd, RTHandle source, RTHandle destination, Texture motionVectors, ref TjsrRenderState renderState, ref Material tjsrMaterial, ref MaterialData materialData)
        {
            SetMaterialData(ref tjsrMaterial, ref materialData);

            bool isNewFrame = materialData.historyData.m_lastUpdateFrameIndex != Time.frameCount;

            if (renderState.config.enableActivePass)
            {
                tjsrMaterial.EnableKeyword(ShaderKeywords.TJSR_HAS_ACTIVE_PASS);
                // 3-pass implementation: Setup pass, Active pass, Upscale pass.
                // The Setup pass calculates dilated depth and dilated motion vector
                // and converts the input color into YCoCg color space
                // and computes the alpha mask for translucent objects if available.
                // The Active pass calculates depth clip values based on current depth and reprojected previous depth
                // and detect shading changed based on Luma history.
                #region Setup
                using (new ProfilingScope(cmd, ProfilingSampler.Get(ShaderPassResources.PassId.TjsrSetup)))
                {
                    tjsrMaterial.SetTexture(ShaderResources._TjsrMotionVectorTex, isNewFrame ? motionVectors : Texture2D.blackTexture);

                    if (renderState.config.enableIntermediateColor)
                    {
                        renderState.shaderPass.mrtSetup[0] = renderState.intermediateRTs.tjsrMotionDepthBuffer;
                        renderState.shaderPass.mrtSetup[1] = renderState.intermediateRTs.tjsrIntermediateColor;
                        // use the depthBuffer of MRT[0] to avoid to render depth
                        CoreUtils.SetRenderTarget(cmd, renderState.shaderPass.mrtSetup, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt.depthBuffer);
                    }
                    else
                    {
                        CoreUtils.SetRenderTarget(cmd, renderState.intermediateRTs.tjsrMotionDepthBuffer, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt.depthBuffer);
                    }
                    if (renderState.shaderPass.idTJSRSetup < 0)
                        renderState.shaderPass.idTJSRSetup = tjsrMaterial.FindPass(ShaderPassResources.kPassNameTJSRSetup);
                    Blitter.BlitTexture(cmd, source, Vector2.one, tjsrMaterial, renderState.shaderPass.idTJSRSetup);
                }
                #endregion

                #region Activate
                using (new ProfilingScope(cmd, ProfilingSampler.Get(ShaderPassResources.PassId.TjsrActive)))
                {
                    tjsrMaterial.SetTexture(ShaderResources._TjsrMotionDepthBuffer, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt);
                    if (renderState.config.enableIntermediateColor)
                    {
                        tjsrMaterial.SetTexture(ShaderResources._TjsrIntermediateColor, renderState.intermediateRTs.tjsrIntermediateColor.rt);
                        tjsrMaterial.SetTexture(ShaderResources._TjsrLumaHistory, materialData.historyData.m_tjsrPrevLumaHistory.rt);
                    }

                    if (renderState.config.enableIntermediateColor)
                    {
                        renderState.shaderPass.mrtActive[0] = renderState.intermediateRTs.tjsrDepthClip;
                        renderState.shaderPass.mrtActive[1] = materialData.historyData.m_tjsrLumaHistory;
                        // use the depthBuffer of MRT[0] to avoid to render depth
                        CoreUtils.SetRenderTarget(cmd, renderState.shaderPass.mrtActive, renderState.intermediateRTs.tjsrDepthClip.rt.depthBuffer);
                    }
                    else
                    {
                        CoreUtils.SetRenderTarget(cmd, renderState.intermediateRTs.tjsrDepthClip, renderState.intermediateRTs.tjsrDepthClip.rt.depthBuffer);
                    }
                    if (renderState.shaderPass.idTJSRActive < 0)
                        renderState.shaderPass.idTJSRActive = tjsrMaterial.FindPass(ShaderPassResources.kPassNameTJSRActive);
                    Blitter.BlitTexture(cmd, source, Vector2.one, tjsrMaterial, renderState.shaderPass.idTJSRActive);
                }
                #endregion
            }
            else
            {
                tjsrMaterial.DisableKeyword(ShaderKeywords.TJSR_HAS_ACTIVE_PASS);
                // 2-pass implementation: Reconstruct pass, Upscale pass.
                // The Reconstruct pass converts the input color into YCoCg color space
                // and calculates depth clip values based on current depth and reprojected previous depth
                // and detect shading changed based on Luma history.
                #region Reconstruct
                using (new ProfilingScope(cmd, ProfilingSampler.Get(ShaderPassResources.PassId.TjsrReconstruct)))
                {
                    tjsrMaterial.SetTexture(ShaderResources._TjsrMotionVectorTex, isNewFrame ? motionVectors : Texture2D.blackTexture);
                    if (renderState.config.enableIntermediateColor)
                        tjsrMaterial.SetTexture(ShaderResources._TjsrLumaHistory, materialData.historyData.m_tjsrPrevLumaHistory.rt);

                    if (renderState.config.enableIntermediateColor)
                    {
                        renderState.shaderPass.mrtRecon[0] = renderState.intermediateRTs.tjsrMotionDepthBuffer;
                        renderState.shaderPass.mrtRecon[1] = renderState.intermediateRTs.tjsrIntermediateColor;
                        renderState.shaderPass.mrtRecon[2] = materialData.historyData.m_tjsrLumaHistory;
                        // use the depthBuffer of MRT[0] to avoid to render depth
                        CoreUtils.SetRenderTarget(cmd, renderState.shaderPass.mrtRecon, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt.depthBuffer);
                    }
                    else
                    {
                        CoreUtils.SetRenderTarget(cmd, renderState.intermediateRTs.tjsrMotionDepthBuffer, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt.depthBuffer);
                    }
                    if (renderState.shaderPass.idTJSRReconstruct < 0)
                        renderState.shaderPass.idTJSRReconstruct = tjsrMaterial.FindPass(ShaderPassResources.kPassNameTJSRReconstruct);
                    Blitter.BlitTexture(cmd, source, Vector2.one, tjsrMaterial, renderState.shaderPass.idTJSRReconstruct);
                }
                #endregion
            }

            // The Upscale pass apply a fast Lanczos filter to neighbor samples in YCoCg color space,
            // to generate the final color by interpolating between the clamped history color and the filtered color.
            #region Upscale
            using (new ProfilingScope(cmd, ProfilingSampler.Get(ShaderPassResources.PassId.TjsrUpscale)))
            {
                tjsrMaterial.SetTexture(ShaderResources._TjsrMotionDepthBuffer, renderState.intermediateRTs.tjsrMotionDepthBuffer.rt);
                if (renderState.config.enableActivePass)
                    tjsrMaterial.SetTexture(ShaderResources._TjsrDepthClip, renderState.intermediateRTs.tjsrDepthClip.rt);
                if (renderState.config.enableIntermediateColor)
                    tjsrMaterial.SetTexture(ShaderResources._TjsrIntermediateColor, renderState.intermediateRTs.tjsrIntermediateColor.rt);
                tjsrMaterial.SetTexture(ShaderResources._TjsrPriorFeedback, materialData.historyData.m_tjsrPriorFeedback.rt);

                if (renderState.debugViewIndex == DebugViewType.HistoryWeight)
                {
                    renderState.shaderPass.mrtUpscale[0] = destination;
                    renderState.shaderPass.mrtUpscale[1] = renderState.intermediateRTs.tjsrDebugView;
                    // use the depthBuffer of MRT[0] to avoid to render depth
                    CoreUtils.SetRenderTarget(cmd, renderState.shaderPass.mrtUpscale, destination.rt.depthBuffer);
                }
                else
                {
                    CoreUtils.SetRenderTarget(cmd, destination, destination.rt.depthBuffer);
                }

                Blitter.BlitTexture(cmd, source, Vector2.one, tjsrMaterial, (int)ShaderPassResources.PassId.TjsrUpscale);
            }
            #endregion

            #region DebugView
            // In the case of DebugViewType.HistoryWeight, the Debug View is rendered in the Upscale Pass.
            if (renderState.debugViewIndex != DebugViewType.Undefined && renderState.debugViewIndex != DebugViewType.HistoryWeight)
            {
                using (new ProfilingScope(cmd, ProfilingSampler.Get(ShaderPassResources.PassId.TjsrDebug)))
                {
                    CoreUtils.SetRenderTarget(cmd, renderState.intermediateRTs.tjsrDebugView, renderState.intermediateRTs.tjsrDebugView.rt.depthBuffer);
                    if (renderState.shaderPass.idTJSRDebugView < 0)
                        renderState.shaderPass.idTJSRDebugView = tjsrMaterial.FindPass(ShaderPassResources.kPassNameTJSRDebugView);
                    Blitter.BlitTexture(cmd, source, Vector2.one, tjsrMaterial, renderState.shaderPass.idTJSRDebugView);
                }
            }
            #endregion

            if (isNewFrame)
            {
                materialData.historyData.m_lastUpdateFrameIndex = Time.frameCount;
                // Swap the history render targets.

                // It's a workaround to fix spots effects in some MTK devices when HDR is on.
                if(destination.rt.graphicsFormat != materialData.historyData.m_tjsrPriorFeedback.rt.graphicsFormat)
                {
                    cmd.Blit(destination, materialData.historyData.m_tjsrPriorFeedback);
                }
                else
                {
                    cmd.CopyTexture(destination, materialData.historyData.m_tjsrPriorFeedback);
                }
                materialData.historyData.SwapHistory();
            }
        }
    }
}
