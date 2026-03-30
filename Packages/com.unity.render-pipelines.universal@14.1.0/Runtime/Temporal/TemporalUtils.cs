
namespace UnityEngine.Rendering.Universal
{
    // The interface of temporal history data that persists over a frame. (per camera)
    internal interface ITemporalPersistentHistory
    {
        public void UpdateTargets(ref CameraData cameraData);

        public void DeallocateTargets();
    }

    internal static class TemporalUtils
    {
        // Note TemporalUtils.ValidateAndWarn should have the same result as UniversalRenderPipeline::CheckTemporalMethod().
        static internal string ValidateAndWarn(ref CameraData cameraData)
        {
            string warning = null;

            if (cameraData.cameraTargetDescriptor.msaaSamples != 1)
            {
                if (cameraData.xr != null && cameraData.xr.enabled)
                    warning = "because MSAA is on. MSAA must be disabled globally for all cameras in XR mode.";
                else
                    warning = "because MSAA is on. Turn MSAA off on the camera or current URP Asset.";
            }

            if (warning == null && cameraData.camera.TryGetComponent<UniversalAdditionalCameraData>(out var additionalCameraData))
            {
                if (additionalCameraData.renderType == CameraRenderType.Overlay ||
                    additionalCameraData.cameraStack.Count > 0)
                {
                    warning = "because camera is stacked.";
                }
            }

            if (warning == null && cameraData.camera.allowDynamicResolution)
                warning = "because camera has dynamic resolution enabled. You can use a constant render scale instead.";

            if (warning == null && !cameraData.postProcessEnabled)
                warning = "because camera has post-processing disabled.";

            //if (warning == null && !cameraData.renderer.SupportsMotionVectors())
            //    warning = "because the renderer does not implement motion vectors. Motion vectors are required.";

            return warning;
        }

        internal static int CalculateTaaFrameIndex(ref TemporalAA.Settings settings)
        {
            // URP supports adding an offset value to the TAA frame index for testing determinism.
            int taaFrameCountOffset = settings.jitterFrameCountOffset;
            return Time.frameCount + taaFrameCountOffset;
        }

        /// <summary>
        /// Helper function that calculates the Temporal-specific jitter pattern associated with the provided frame index.
        /// </summary>
        /// <param name="frameIndex">Index of the current frame</param>
        /// <returns>Jitter pattern for the provided frame index</returns>
        internal static Vector2 CalculateJitter(int frameIndex)
        {
            // The variance between 0 and the actual halton sequence values reveals noticeable
            // instability in Unity's shadow maps, so we avoid index 0.
            float jitterX = HaltonSequence.Get((frameIndex & 1023) + 1, 2) - 0.5f;
            float jitterY = HaltonSequence.Get((frameIndex & 1023) + 1, 3) - 0.5f;

            return new Vector2(jitterX, jitterY);
        }

        static internal Matrix4x4 CalculateJitterMatrix(ref CameraData cameraData)
        {
            Matrix4x4 jitterMat = Matrix4x4.identity;

            bool isJitter = cameraData.temporalMethod != TemporalMethod.None;
            if (isJitter)
            {
                int frameIndex = CalculateTaaFrameIndex(ref cameraData.taaSettings);

                float actualWidth = cameraData.cameraTargetDescriptor.width;
                float actualHeight = cameraData.cameraTargetDescriptor.height;
                float jitterScale = cameraData.taaSettings.jitterScale;

                var jitter = CalculateJitter(frameIndex);

                // TJSR jitter would not be influenced by TAA settings jitter scale.
                if (cameraData.temporalMethod is TemporalMethod.TAA or TemporalMethod.MetalFXTemporal)
                    jitter *= jitterScale;

                float offsetX = jitter.x * (2.0f / actualWidth);
                float offsetY = jitter.y * (2.0f / actualHeight);

                jitterMat = Matrix4x4.Translate(new Vector3(offsetX, offsetY, 0.0f));
            }

            return jitterMat;
        }
    }
}
