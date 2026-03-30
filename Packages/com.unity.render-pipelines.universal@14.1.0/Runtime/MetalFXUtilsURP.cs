namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// Utility functions for Apple MetalFX upscaling in URP.
    /// </summary>
    public static class MetalFXUtilsURP
    {
        /// <summary>
        /// Checks if MetalFX is requested on a specific camera (MetalFX should only be requested on the final rendering game camera).
        /// </summary>
        /// <returns>True if MetalFX is requested on the given camera</returns>
        public static bool IsRequestedForCamera(ref CameraData cameraData)
        {
            return cameraData is
            {
                cameraType: CameraType.Game,
                imageScalingMode: ImageScalingMode.Upscaling,
                upscalingFilter: ImageUpscalingFilter.MetalFXSpatial or ImageUpscalingFilter.MetalFXTemporal
            };
        }

        internal static string ValidateAndWarn(ref CameraData cameraData)
        {
            if (!MetalFXCoreUtils.IsSupported())
            {
                return "MetalFX not enabled: MetalFX is not supported on this device.";
            }

            if (!cameraData.postProcessEnabled)
                return $"MetalFX not enabled: Post-processing is not enabled for camera {cameraData.camera.gameObject.name}.";

            if (cameraData.upscalingFilter == ImageUpscalingFilter.MetalFXTemporal)
            {
                if (cameraData.temporalMethod != TemporalMethod.MetalFXTemporal)
                    return "MetalFX temporal not enabled because no temporal post-processing method is active.\n" + TemporalUtils.ValidateAndWarn(ref cameraData);

                // Render scale should already be checked during initialization.
            }

            return null;
        }

        /// <summary>
        /// Calculate the jitter offset (ranging from -0.5 to 0.5) for current frame.
        /// Use TAA's method to calculate jitter.
        /// </summary>
        /// <param name="cameraData">The camera data</param>
        /// <returns>The jitter offset, ranging from -0.5 to 0.5.</returns>
        internal static Vector2 CalculateJitter(ref CameraData cameraData)
        {
            return TemporalUtils.CalculateJitter(TemporalUtils.CalculateTaaFrameIndex(ref cameraData.taaSettings)) *
                   cameraData.taaSettings.jitterScale;
        }
    }
}
