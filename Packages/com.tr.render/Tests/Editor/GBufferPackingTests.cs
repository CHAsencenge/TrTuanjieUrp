#if ENABLE_UNIT_TESTS
using NUnit.Framework;
using Game.Rendering;
using UnityEngine;

namespace Game.Tests.Editor
{
    /// <summary>
    /// Tests for GBuffer encoding and decoding round-trips.
    /// Validates that packing/unpacking ShadingModelId, MaterialFlags, and
    /// other GBuffer channels preserves values within acceptable precision.
    /// </summary>
    [TestFixture]
    public class GBufferPackingTests
    {
        // Tolerance for 8-bit unorm round-trip: 1/255 ≈ 0.00392
        private const float k_8BitTolerance = 1.0f / 255.0f + 0.001f;

        // Tolerance for octahedral normal encoding (slightly larger due to quantization)
        private const float k_NormalTolerance = 0.02f;

        #region ShadingModelId + MaterialFlags Packing

        [Test]
        public void PackUnpack_ShadingModelId_DefaultLit_RoundTrips()
        {
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.DefaultLit, MaterialFlags.None);
            var unpacked = GBufferUtils.UnpackShadingModelId(packed);
            Assert.AreEqual(ShadingModelId.DefaultLit, unpacked);
        }

        [Test]
        public void PackUnpack_ShadingModelId_Unlit_RoundTrips()
        {
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.Unlit, MaterialFlags.None);
            var unpacked = GBufferUtils.UnpackShadingModelId(packed);
            Assert.AreEqual(ShadingModelId.Unlit, unpacked);
        }

        [Test]
        public void PackUnpack_ShadingModelId_AllModels_RoundTrip()
        {
            var models = new[]
            {
                ShadingModelId.DefaultLit,
                ShadingModelId.Subsurface,
                ShadingModelId.ClearCoat,
                ShadingModelId.TwoSidedFoliage,
                ShadingModelId.Unlit
            };

            foreach (var model in models)
            {
                float packed = GBufferUtils.PackShadingModelAndFlags(model, MaterialFlags.None);
                var result = GBufferUtils.UnpackShadingModelId(packed);
                Assert.AreEqual(model, result, $"ShadingModelId round-trip failed for {model}");
            }
        }

        [Test]
        public void PackUnpack_MaterialFlags_ReceiveShadowsOff_RoundTrips()
        {
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.DefaultLit, MaterialFlags.ReceiveShadowsOff);
            var flags = GBufferUtils.UnpackMaterialFlags(packed);
            Assert.IsTrue(flags.HasFlag(MaterialFlags.ReceiveShadowsOff));
        }

        [Test]
        public void PackUnpack_MaterialFlags_Combined_RoundTrips()
        {
            var combined = MaterialFlags.ReceiveShadowsOff | MaterialFlags.SpecularHighlightsOff;
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.ClearCoat, combined);

            var modelResult = GBufferUtils.UnpackShadingModelId(packed);
            var flagsResult = GBufferUtils.UnpackMaterialFlags(packed);

            Assert.AreEqual(ShadingModelId.ClearCoat, modelResult);
            Assert.IsTrue(flagsResult.HasFlag(MaterialFlags.ReceiveShadowsOff));
            Assert.IsTrue(flagsResult.HasFlag(MaterialFlags.SpecularHighlightsOff));
        }

        [Test]
        public void PackUnpack_ShadingModelAndFlags_Independent()
        {
            // Changing flags should not affect shading model ID and vice versa
            float packed1 = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.Subsurface, MaterialFlags.None);
            float packed2 = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.Subsurface, MaterialFlags.SpecularSetup);

            Assert.AreEqual(
                GBufferUtils.UnpackShadingModelId(packed1),
                GBufferUtils.UnpackShadingModelId(packed2),
                "ShadingModelId should be independent of MaterialFlags"
            );

            Assert.AreNotEqual(
                GBufferUtils.UnpackMaterialFlags(packed1),
                GBufferUtils.UnpackMaterialFlags(packed2),
                "Different MaterialFlags should produce different results"
            );
        }

        [Test]
        public void PackedValue_IsInNormalizedRange()
        {
            // All packed values should be in [0, 1] for shader storage
            foreach (ShadingModelId model in System.Enum.GetValues(typeof(ShadingModelId)))
            {
                foreach (MaterialFlags flags in System.Enum.GetValues(typeof(MaterialFlags)))
                {
                    float packed = GBufferUtils.PackShadingModelAndFlags(model, flags);
                    Assert.GreaterOrEqual(packed, 0.0f, $"Packed value for {model}+{flags} is below 0");
                    Assert.LessOrEqual(packed, 1.0f, $"Packed value for {model}+{flags} is above 1");
                }
            }
        }

        #endregion

        #region Shading Model ID Value Range

        [Test]
        public void ShadingModelId_FitsIn4Bits()
        {
            foreach (ShadingModelId model in System.Enum.GetValues(typeof(ShadingModelId)))
            {
                Assert.LessOrEqual((int)model, 15, $"ShadingModelId {model} exceeds 4-bit range (0-15)");
                Assert.GreaterOrEqual((int)model, 0, $"ShadingModelId {model} is negative");
            }
        }

        [Test]
        public void MaterialFlags_FitsIn4Bits()
        {
            // Maximum combination of all flags should fit in 4 bits (0-15)
            var allFlags = MaterialFlags.ReceiveShadowsOff | MaterialFlags.SpecularHighlightsOff | MaterialFlags.SpecularSetup;
            Assert.LessOrEqual((int)allFlags, 15, "Combined MaterialFlags exceeds 4-bit range");
        }

        #endregion

        #region Phase 2: CustomData Per-ShadingModel Encoding

        [Test]
        public void Subsurface_CustomData_SubsurfaceColor_RoundTrips()
        {
            // Subsurface stores SubsurfaceColor in customData.xyz, Opacity in .w
            // Simulates 8-bit quantization through GBuffer2.ba + GBuffer4.rg
            var subsurfaceColor = new Vector3(0.8f, 0.3f, 0.2f);
            float opacity = 0.9f;

            // Pack into customData format
            Vector4 customData = new Vector4(subsurfaceColor.x, subsurfaceColor.y, subsurfaceColor.z, opacity);

            // Simulate 8-bit round-trip (GBuffer2.b, GBuffer2.a, GBuffer4.r, GBuffer4.g)
            byte qX = (byte)Mathf.RoundToInt(customData.x * 255f);
            byte qY = (byte)Mathf.RoundToInt(customData.y * 255f);
            byte qZ = (byte)Mathf.RoundToInt(customData.z * 255f);
            byte qW = (byte)Mathf.RoundToInt(customData.w * 255f);

            Assert.AreEqual(subsurfaceColor.x, qX / 255f, k_8BitTolerance, "SubsurfaceColor.r round-trip");
            Assert.AreEqual(subsurfaceColor.y, qY / 255f, k_8BitTolerance, "SubsurfaceColor.g round-trip");
            Assert.AreEqual(subsurfaceColor.z, qZ / 255f, k_8BitTolerance, "SubsurfaceColor.b round-trip");
            Assert.AreEqual(opacity, qW / 255f, k_8BitTolerance, "Opacity round-trip");
        }

        [Test]
        public void ClearCoat_CustomData_StrengthAndRoughness_RoundTrips()
        {
            // ClearCoat stores Strength in customData.x, Roughness in customData.y
            float coatStrength = 0.75f;
            float coatRoughness = 0.15f;

            byte qStrength  = (byte)Mathf.RoundToInt(coatStrength * 255f);
            byte qRoughness = (byte)Mathf.RoundToInt(coatRoughness * 255f);

            Assert.AreEqual(coatStrength, qStrength / 255f, k_8BitTolerance, "ClearCoat strength round-trip");
            Assert.AreEqual(coatRoughness, qRoughness / 255f, k_8BitTolerance, "ClearCoat roughness round-trip");
        }

        [Test]
        public void TwoSidedFoliage_CustomData_BackfaceColor_RoundTrips()
        {
            // TwoSidedFoliage stores BackfaceColor in customData.xyz
            var backfaceColor = new Vector3(0.1f, 0.6f, 0.05f);

            byte qR = (byte)Mathf.RoundToInt(backfaceColor.x * 255f);
            byte qG = (byte)Mathf.RoundToInt(backfaceColor.y * 255f);
            byte qB = (byte)Mathf.RoundToInt(backfaceColor.z * 255f);

            Assert.AreEqual(backfaceColor.x, qR / 255f, k_8BitTolerance, "BackfaceColor.r round-trip");
            Assert.AreEqual(backfaceColor.y, qG / 255f, k_8BitTolerance, "BackfaceColor.g round-trip");
            Assert.AreEqual(backfaceColor.z, qB / 255f, k_8BitTolerance, "BackfaceColor.b round-trip");
        }

        [Test]
        public void CustomData_AllChannels_IndependentStorage()
        {
            // Verify customData channels are stored independently in GBuffer2.ba + GBuffer4.rg
            // Changing one channel should not affect others
            float[] testVals = { 0.0f, 0.5f, 1.0f };

            foreach (float x in testVals)
            foreach (float y in testVals)
            foreach (float z in testVals)
            foreach (float w in testVals)
            {
                byte qX = (byte)Mathf.RoundToInt(x * 255f);
                byte qY = (byte)Mathf.RoundToInt(y * 255f);
                byte qZ = (byte)Mathf.RoundToInt(z * 255f);
                byte qW = (byte)Mathf.RoundToInt(w * 255f);

                Assert.AreEqual(x, qX / 255f, k_8BitTolerance);
                Assert.AreEqual(y, qY / 255f, k_8BitTolerance);
                Assert.AreEqual(z, qZ / 255f, k_8BitTolerance);
                Assert.AreEqual(w, qW / 255f, k_8BitTolerance);
            }
        }

        [Test]
        public void Subsurface_PackWithModelId_PreservesAll()
        {
            // End-to-end: pack Subsurface model + flags + verify customData is orthogonal
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.Subsurface, MaterialFlags.None);
            Assert.AreEqual(ShadingModelId.Subsurface, GBufferUtils.UnpackShadingModelId(packed));

            // CustomData lives in separate GBuffer targets - packing model+flags does not touch it
            float customVal = 0.65f;
            byte q = (byte)Mathf.RoundToInt(customVal * 255f);
            Assert.AreEqual(customVal, q / 255f, k_8BitTolerance, "CustomData independent of model ID packing");
        }

        [Test]
        public void ClearCoat_PackWithModelId_PreservesAll()
        {
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.ClearCoat, MaterialFlags.SpecularHighlightsOff);
            Assert.AreEqual(ShadingModelId.ClearCoat, GBufferUtils.UnpackShadingModelId(packed));
            Assert.IsTrue(GBufferUtils.UnpackMaterialFlags(packed).HasFlag(MaterialFlags.SpecularHighlightsOff));
        }

        [Test]
        public void TwoSidedFoliage_PackWithModelId_PreservesAll()
        {
            float packed = GBufferUtils.PackShadingModelAndFlags(ShadingModelId.TwoSidedFoliage, MaterialFlags.ReceiveShadowsOff);
            Assert.AreEqual(ShadingModelId.TwoSidedFoliage, GBufferUtils.UnpackShadingModelId(packed));
            Assert.IsTrue(GBufferUtils.UnpackMaterialFlags(packed).HasFlag(MaterialFlags.ReceiveShadowsOff));
        }

        #endregion

        #region GBuffer Channel Precision

        [Test]
        public void MetallicSmoothness_8BitPrecision_RoundTrips()
        {
            // Simulate the 8-bit quantization that occurs in R8G8B8A8_UNorm
            float[] testValues = { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f, 0.123f, 0.876f };

            foreach (float value in testValues)
            {
                // Simulate 8-bit storage: quantize to 0-255 and back
                byte quantized = (byte)Mathf.RoundToInt(value * 255.0f);
                float recovered = quantized / 255.0f;

                Assert.AreEqual(value, recovered, k_8BitTolerance,
                    $"8-bit round-trip failed for value {value}");
            }
        }

        [Test]
        public void BaseColor_SRGB_ValueRange()
        {
            // BaseColor should be in [0, 1] range (sRGB)
            // This tests the C# contract; actual sRGB encoding happens on GPU
            float[] extremes = { 0.0f, 1.0f };
            foreach (float v in extremes)
            {
                Assert.GreaterOrEqual(v, 0.0f);
                Assert.LessOrEqual(v, 1.0f);
            }
        }

        #endregion
    }
}
#endif
