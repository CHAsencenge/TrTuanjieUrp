using System;
using System.Buffers.Text;

namespace UnityEngine.Rendering.Universal
{

    /// <summary>
    /// The resolution at which URP computes the Screen Space Lens Flare effect.
    /// </summary>
    public enum ScreenSpaceLensFlareResolution : int
    {
        /// <summary>
        /// Half Resolution.
        /// </summary>
        Half = 1,

        /// <summary>
        /// Quarter Resolution.
        /// </summary>
        Quarter = 2,

        /// <summary>
        /// Eigtht Resolution.
        /// </summary>
        Eighth = 3
    }

    /// <summary>
    /// A volume component that holds settings for the ScreenSpaceLensFlare effect.
    /// </summary>
    [Serializable, VolumeComponentMenuForRenderPipeline("Post-processing/ScreenSpaceLensFlare", typeof(UniversalRenderPipeline))]
    [URPHelpURL("post-processing-Screen-Space-Lens-Flare")]
    public sealed partial class ScreenSpaceLensFlare : VolumeComponent, IPostProcessComponent
    {
        /// <summary>
        /// Controls the brightness scaling of the Screen Space Lens Flare effect.
        /// When the value is set to 0, the effect will be disabled entirely.
        /// The default value is 0f.
        /// </summary>
        [Tooltip("Controls the brightness scale of the Screen Space Lens Flare effect. When set to 0, the effect is disabled.")]
        public MinFloatParameter intensity = new MinFloatParameter(0f, 0f);

        /// <summary>
        /// Tints the color of the Screen Space Lens Flare effect.
        /// The RGB values are chromatically normalized, with luminance discarded.
        /// The default value is Color.white.
        /// </summary>
        [Tooltip("Tints the color of the Screen Space Lens Flare effect. The RGB values are chromatically normalized, with luminance discarded.")]
        public ColorParameter tintColor = new ColorParameter(Color.white);

        /// <summary>
        /// Controls the Bloom mipmap level used as the source texture for the Screen Space Lens Flare effect.
        /// A Higher value produces blurrier result for all the flares.
        /// The default vlaue is mipmap 1.
        /// </summary>
        [Tooltip("Controls the Bloom mipmap level used as the source texture for the Screen Space Lens Flare effect. A Higher value produces blurrier result for all the flares.")]
        public ClampedIntParameter bloomMipBias = new ClampedIntParameter(1, 1, 5);

        /// <summary>
        /// </summary>
        [Header("Ghost")]
        /// <summary>
        /// Controls the intensity of the source-aligned Ghost Flare sample
        /// Those flares are sampled using scaled screen coordinates.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the intensity of the source-aligned Ghost Flare sample. Those flares are sampled using scaled screen coordinates.")]
        public MinFloatParameter regularMultiplier = new MinFloatParameter(1f, 0f);
        /// <summary>
        /// Controls the intensity of source-opposed flare elements.
        /// Those flares are sampled using centrally symmetric screen coordinates.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the intensity of the source-opposed Ghost Flare sample. Those flares are sampled using centrally symmetric screen coordinates.")]
        public MinFloatParameter reversedMultiplier = new MinFloatParameter(1f, 0f);
        /// <summary>
        /// Controls the intensity of the Halo Flare sample. Those flares are sampled using polar screen coordinates.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the intensity of the Halo Flare sample. Those flares are sampled using polar screen coordinates.")]
        public MinFloatParameter haloMultiplier = new MinFloatParameter(1f, 0f);
        /// <summary>
        /// Controls the scaling factor for the Halo Flare sample.
        /// Equal X,Y values makes the flare circular.
        /// Default value is (1f, 1f)
        /// </summary>
        [AdditionalProperty]
        [Tooltip("Controls the scaling factor for the Halo Flare sample. Equal X/Y values maintain circular flares.")]
        public Vector2Parameter haloScale = new Vector2Parameter(new Vector2(1f, 1f));
        /// <summary>
        /// Controls the quantity of Flares to be rendered.
        /// Those flares maintain uniform screen-space distribution.
        /// This parameter has a strong impact on performance.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the quantity of Flares to be rendered. Those flares maintain uniform screen-space distribution. This parameter has a strong impact on performance.")]
        public ClampedIntParameter samples = new ClampedIntParameter(1, 1, 3);
        /// <summary>
        /// Controls the value by which each additional sample is multiplied.
        /// A value of 1 keep the same intensities for all samples.
        /// A value of 0.7 multiplies the first sample by 1 (0.7 power 0), the second sample by 0.7 (0.7 power 1) and the third sample by 0.49 (0.7 power 2).
        /// </summary>
        [AdditionalProperty]
        [Tooltip("Controls the attenuation factor by which each additional sample multiples by. Higher values slow the intensity decay between samples")]
        public ClampedFloatParameter sampleDimmer = new ClampedFloatParameter(0.5f, 0.1f, 1f);
        /// <summary>
        /// Controls the starting UV offset distance of the flares in screen space relative to their source. 
        /// Measured in percentage of screen dimensions. (e.g., 0.1 = 10% of screen width/height).
        /// Default value is 1.25f.
        /// </summary>
        [Tooltip("Controls the starting UV offset distance of the flares in screen space relative to their source. This parameter measured in percentage of screen dimensions.")]
        public ClampedFloatParameter startingPoint = new ClampedFloatParameter(1.25f, 0f, 2f);
        /// <summary>
        /// Controls the scaling factor for Ghost Flares.
        /// A value of 1.0 maintains original UV coordinates through identity scaling transformation.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the scaling factor for Ghost Flares. A value of 1.0 maintains original UV coordinates through identity scaling transformation.")]
        public MinFloatParameter ghostScale = new MinFloatParameter(1f, 0f);
        /// <summary>
        /// Controls the intensity of the vignette effect to occlude the Lens Flare effect at the center of the screen.
        /// Default value is 1f.
        /// </summary>
        [Tooltip("Controls the intensity of the vignette effect to occlude the Lens Flare effect at the center of the screen.")]
        public ClampedFloatParameter vignetteIntensity = new ClampedFloatParameter(1f, 0f, 1f);
        /// <summary>
        /// Controls the scaling factor for vignette coverage.
        /// Higher values expand darkening coverage (X: Horizontal vignette coverage, Y: Vertical vignette coverage).
        /// Default value is (1f, 1f).
        /// </summary>
        [AdditionalProperty]
        [Tooltip("Controls the scaling factor for the vignette coverage. Higher values increase vignette coverage")]
        public Vector2Parameter vignetteScale = new Vector2Parameter(new Vector2(1f, 1f));

        /// <summary>
        /// </summary>
        [Header("Glare")]
        /// <summary>
        /// Controls the intensity of the Glare effect.
        /// This effect has an impact on performance when above zero.
        /// When set to 0, the effect is disabled.
        /// Default value is 0f.
        /// </summary>
        [Tooltip("Controls the intensity of the Glare effect. This effect has an impact on performance when above zero. When set to 0, the effect is disabled.")]
        public MinFloatParameter glareMultiplier = new MinFloatParameter(0f, 0f);
        /// <summary>
        /// Controls the length of the Glare effect.
        /// Default value is 0.5f.
        /// </summary>
        [Tooltip("Controls the length of the Glare effect. A value of 1.0 creates Glares about the width of the screen.")]
        public ClampedFloatParameter length = new ClampedFloatParameter(0.5f, 0f, 1f);
        /// <summary>
        /// Controls the orientation of the Glare effect in degrees.
        /// A value of 0.0 produces horizontal glares.
        /// Default value is 0f.
        /// </summary>
        [Tooltip("Controls the orientation of the Glare effect in degrees. A value of 0.0 produces horizontal glares.")]
        public ClampedFloatParameter orientation = new ClampedFloatParameter(0f, 0f, 180f);
        /// <summary>
        /// Controls the luminance threshold of the Glare effect in gamma-space.
        /// This parameter discards pixels with luminance below this threshold.
        /// Default value is 0.5f.
        /// </summary>
        [Tooltip("Controls the luminance threshold of the Glare effect in gamma-space. This parameter discards pixels with luminance below this threshold.")]
        public MinFloatParameter glareThreshold = new MinFloatParameter(0.5f, 0f);
        /// <summary>
        /// Controls the resolution of the Glare effect is evaluated..
        /// Default value is Quarter.
        /// </summary>
        [SerializeField]
        [AdditionalProperty]
        [Tooltip("Controls the resolution of the Glare effect is evaluated. A value of the \"Quarter\" renders at 25% scale")]
        public ScreenSpaceLensFlareResolutionParameter resolution = new ScreenSpaceLensFlareResolutionParameter(ScreenSpaceLensFlareResolution.Quarter);

        /// <summary>
        /// </summary>
        [Header("Chromatic Aberration")]
        /// <summary>
        /// Controls the strength of the Chromatic Aberration effect.
        /// Higher values increase RGB channel separation at screen edges.
        /// Default value is 0.5f.
        /// </summary>
        [Tooltip("Controls the strength of the Chromatic Aberration effect. Higher values increase RGB channel separation at screen edges.")]
        public ClampedFloatParameter chromatic = new ClampedFloatParameter(0.5f, 0f, 1f);

        /// <inheritdoc/>
        public bool IsActive() => intensity.value > 0f;

        public bool IsGlareActive() => glareMultiplier.value > 0f;

        /// <inheritdoc/>
        public bool IsTileCompatible() => false;
    }

    /// <summary>
    /// A <see cref="VolumeParameter"/> that holds a <see cref="ScreenSpaceLensFlareResolution"/> value.
    /// </summary>
    [Serializable]
    public sealed class ScreenSpaceLensFlareResolutionParameter : VolumeParameter<ScreenSpaceLensFlareResolution>
    {
        /// <summary>
        /// Creates a new <see cref="ScreenSpaceLensFlareResolutionParameter"/> instance.
        /// </summary>
        /// <param name="value">The initial value to store in the parameter.</param>
        /// <param name="overrideState">The initial override state for the parameter.</param>
        public ScreenSpaceLensFlareResolutionParameter(ScreenSpaceLensFlareResolution value, bool overrideState = false) : base(value, overrideState) { }
    }
}
