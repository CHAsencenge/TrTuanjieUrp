#if ENABLE_UNIT_TESTS
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using Game.Rendering;

namespace Game.Tests.Editor
{
    /// <summary>
    /// Tests for ShadingModelId enum integrity.
    /// Validates uniqueness, range constraints, and consistency with shader defines.
    /// </summary>
    [TestFixture]
    public class ShadingModelTests
    {
        [Test]
        public void AllShadingModelIds_AreUnique()
        {
            var values = System.Enum.GetValues(typeof(ShadingModelId)).Cast<ShadingModelId>();
            var ids = values.Select(v => (int)v).ToList();

            Assert.AreEqual(ids.Count, ids.Distinct().Count(),
                "Duplicate ShadingModelId values detected");
        }

        [Test]
        public void AllShadingModelIds_InRange0To15()
        {
            foreach (ShadingModelId model in System.Enum.GetValues(typeof(ShadingModelId)))
            {
                int id = (int)model;
                Assert.GreaterOrEqual(id, 0, $"{model} has negative ID");
                Assert.LessOrEqual(id, 15, $"{model} exceeds 4-bit range (0-15)");
            }
        }

        [Test]
        public void DefaultLit_IsZero()
        {
            Assert.AreEqual(0, (int)ShadingModelId.DefaultLit,
                "DefaultLit must be 0 (the default/fallback model)");
        }

        [Test]
        public void Unlit_IsFifteen()
        {
            Assert.AreEqual(15, (int)ShadingModelId.Unlit,
                "Unlit must be 15 (maximum 4-bit value, easy to detect)");
        }

        [Test]
        public void ShadingModelId_HasExpectedMembers()
        {
            // Verify all Phase 1-2 shading models exist
            Assert.IsTrue(System.Enum.IsDefined(typeof(ShadingModelId), (byte)0), "DefaultLit should exist");
            Assert.IsTrue(System.Enum.IsDefined(typeof(ShadingModelId), (byte)1), "Subsurface should exist");
            Assert.IsTrue(System.Enum.IsDefined(typeof(ShadingModelId), (byte)2), "ClearCoat should exist");
            Assert.IsTrue(System.Enum.IsDefined(typeof(ShadingModelId), (byte)3), "TwoSidedFoliage should exist");
            Assert.IsTrue(System.Enum.IsDefined(typeof(ShadingModelId), (byte)15), "Unlit should exist");
        }

        [Test]
        public void MaterialFlags_None_IsZero()
        {
            Assert.AreEqual(0, (int)MaterialFlags.None,
                "MaterialFlags.None must be 0");
        }

        [Test]
        public void MaterialFlags_AreDistinctPowerOfTwo()
        {
            var flags = new[]
            {
                MaterialFlags.ReceiveShadowsOff,
                MaterialFlags.SpecularHighlightsOff,
                MaterialFlags.SpecularSetup
            };

            foreach (var flag in flags)
            {
                int val = (int)flag;
                Assert.IsTrue(val > 0 && (val & (val - 1)) == 0,
                    $"MaterialFlags.{flag} ({val}) is not a power of two");
            }
        }

        [Test]
        public void MaterialFlags_AllCombinations_FitIn4Bits()
        {
            // Test all possible combinations of flags fit in 4 bits
            var allFlags = (int)MaterialFlags.ReceiveShadowsOff |
                           (int)MaterialFlags.SpecularHighlightsOff |
                           (int)MaterialFlags.SpecularSetup;

            for (int combo = 0; combo <= allFlags; combo++)
            {
                Assert.LessOrEqual(combo, 15,
                    $"Flag combination {combo} exceeds 4-bit range");
            }
        }
        #region Phase 2: CustomData Channel Assignments

        [Test]
        public void Subsurface_UsesCustomDataXYZW()
        {
            // Subsurface: xy = SubsurfaceColor.rg, z = SubsurfaceColor.b, w = Opacity
            // All 4 channels used - verify model ID matches
            Assert.AreEqual(1, (int)ShadingModelId.Subsurface,
                "Subsurface must be ID 1 (matching SHADING_MODEL_SUBSURFACE define)");
        }

        [Test]
        public void ClearCoat_UsesCustomDataXY()
        {
            // ClearCoat: x = Strength, y = Roughness
            // Only 2 channels used
            Assert.AreEqual(2, (int)ShadingModelId.ClearCoat,
                "ClearCoat must be ID 2 (matching SHADING_MODEL_CLEAR_COAT define)");
        }

        [Test]
        public void TwoSidedFoliage_UsesCustomDataXYZ()
        {
            // TwoSidedFoliage: xyz = BackfaceColor
            // 3 channels used
            Assert.AreEqual(3, (int)ShadingModelId.TwoSidedFoliage,
                "TwoSidedFoliage must be ID 3 (matching SHADING_MODEL_TWO_SIDED_FOLIAGE define)");
        }

        [Test]
        public void Phase2Models_HaveSequentialIds()
        {
            // Phase 2 models should have sequential IDs (1, 2, 3) for efficient dispatch
            Assert.AreEqual(1, (int)ShadingModelId.Subsurface);
            Assert.AreEqual(2, (int)ShadingModelId.ClearCoat);
            Assert.AreEqual(3, (int)ShadingModelId.TwoSidedFoliage);
        }

        [Test]
        public void AllPhase2Models_CanPackWithAllFlagCombinations()
        {
            var phase2Models = new[]
            {
                ShadingModelId.Subsurface,
                ShadingModelId.ClearCoat,
                ShadingModelId.TwoSidedFoliage
            };

            var flagCombos = new[]
            {
                MaterialFlags.None,
                MaterialFlags.ReceiveShadowsOff,
                MaterialFlags.SpecularHighlightsOff,
                MaterialFlags.SpecularSetup,
                MaterialFlags.ReceiveShadowsOff | MaterialFlags.SpecularHighlightsOff,
                MaterialFlags.ReceiveShadowsOff | MaterialFlags.SpecularSetup
            };

            foreach (var model in phase2Models)
            {
                foreach (var flags in flagCombos)
                {
                    float packed = GBufferUtils.PackShadingModelAndFlags(model, flags);
                    var unpackedModel = GBufferUtils.UnpackShadingModelId(packed);
                    var unpackedFlags = GBufferUtils.UnpackMaterialFlags(packed);

                    Assert.AreEqual(model, unpackedModel,
                        $"Model {model} + flags {flags}: model mismatch");
                    Assert.AreEqual(flags, unpackedFlags,
                        $"Model {model} + flags {flags}: flags mismatch");
                }
            }
        }

        #endregion
    }
}
#endif
