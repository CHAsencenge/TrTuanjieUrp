using System.Linq;
using UnityEditor.PackageManager.UI;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.UIElements;

namespace UnityEditor.Rendering.Universal
{
    [CustomEditor(typeof(ScreenSpaceLensFlare))]
    sealed class ScreenSpaceLensFlareEditor : VolumeComponentEditor
    {
        SerializedDataParameter m_Intensity;
        SerializedDataParameter m_TintColor;
        SerializedDataParameter m_BloomMipBias;

        SerializedDataParameter m_RegularMultiplier;
        SerializedDataParameter m_ReversedMultiplier;
        SerializedDataParameter m_HalodMultiplier;
        SerializedDataParameter m_HaloScale;
        SerializedDataParameter m_Samples;
        SerializedDataParameter m_SampleDimmer;
        SerializedDataParameter m_StartingPoint;
        SerializedDataParameter m_GhostScale;
        SerializedDataParameter m_VignetteIntensity;
        SerializedDataParameter m_VignetteScale;

        SerializedDataParameter m_GlareMultiplier;
        SerializedDataParameter m_Length;
        SerializedDataParameter m_Orientation;
        SerializedDataParameter m_GlareThreshold;
        SerializedDataParameter m_Resolution;

        SerializedDataParameter m_Chromatic;

        public override void OnEnable()
        {
            var o = new PropertyFetcher<ScreenSpaceLensFlare>(serializedObject);

            m_Intensity = Unpack(o.Find(x => x.intensity));
            m_TintColor = Unpack(o.Find(x => x.tintColor));
            m_BloomMipBias = Unpack(o.Find(x => x.bloomMipBias));

            m_RegularMultiplier = Unpack(o.Find(x => x.regularMultiplier));
            m_ReversedMultiplier = Unpack(o.Find(x => x.reversedMultiplier));
            m_HalodMultiplier = Unpack(o.Find(x => x.haloMultiplier));
            m_HaloScale = Unpack(o.Find(x => x.haloScale));
            m_Samples = Unpack(o.Find(x => x.samples));
            m_SampleDimmer = Unpack(o.Find(x => x.sampleDimmer));
            m_StartingPoint = Unpack(o.Find(x => x.startingPoint));
            m_GhostScale = Unpack(o.Find(x => x.ghostScale));
            m_VignetteIntensity = Unpack(o.Find(x => x.vignetteIntensity));
            m_VignetteScale = Unpack(o.Find(x => x.vignetteScale));

            m_GlareMultiplier = Unpack(o.Find(x => x.glareMultiplier));
            m_Length = Unpack(o.Find(x => x.length));
            m_Orientation = Unpack(o.Find(x => x.orientation));
            m_GlareThreshold = Unpack(o.Find(x => x.glareThreshold));
            m_Resolution = Unpack(o.Find(x => x.resolution));

            m_Chromatic = Unpack(o.Find(x => x.chromatic));
        }

        public override void OnInspectorGUI()
        {
            PropertyField(m_Intensity);
            PropertyField(m_TintColor);
            PropertyField(m_BloomMipBias);

            // Ghost Flares
            PropertyField(m_RegularMultiplier);
            PropertyField(m_ReversedMultiplier);
            PropertyField(m_HalodMultiplier);
            if (showAdditionalProperties)
            {
                using (new IndentLevelScope())
                {
                    PropertyField(m_HaloScale);
                }
            }
            PropertyField(m_Samples);
            if (showAdditionalProperties)
            {
                using (new IndentLevelScope())
                {
                    PropertyField(m_SampleDimmer);
                }
            }
            PropertyField(m_StartingPoint);
            PropertyField(m_GhostScale);
            PropertyField(m_VignetteIntensity);
            if (showAdditionalProperties)
            {
                using (new IndentLevelScope())
                {
                    PropertyField(m_VignetteScale);
                }
            }

            // Glares
            PropertyField(m_GlareMultiplier);
            using (new IndentLevelScope())
            {
                PropertyField(m_Length);
                PropertyField(m_Orientation);
                PropertyField(m_GlareThreshold);
                PropertyField(m_Resolution);
            }

            // Chromatic Aberration
            PropertyField(m_Chromatic);
        }
    }
}
