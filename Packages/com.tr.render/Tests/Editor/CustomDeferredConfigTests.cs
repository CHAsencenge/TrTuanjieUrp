#if ENABLE_UNIT_TESTS
using NUnit.Framework;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using Game.Rendering;

namespace Game.Tests.Editor
{
    /// <summary>
    /// Tests for CustomDeferredConfig ScriptableObject.
    /// Validates GBuffer format configurations for PC and Mobile platforms.
    /// </summary>
    [TestFixture]
    public class CustomDeferredConfigTests
    {
        private CustomDeferredConfig _pcConfig;
        private CustomDeferredConfig _mobileConfig;

        [SetUp]
        public void SetUp()
        {
            _pcConfig = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            // Default is PC profile

            _mobileConfig = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            // Use reflection to set Mobile profile since the field is private
            var fieldInfo = typeof(CustomDeferredConfig).GetField("_platformProfile",
                System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            fieldInfo.SetValue(_mobileConfig, CustomDeferredConfig.PlatformProfile.Mobile);
        }

        [TearDown]
        public void TearDown()
        {
            Object.DestroyImmediate(_pcConfig);
            Object.DestroyImmediate(_mobileConfig);
        }

        #region GBuffer Count

        [Test]
        public void PCConfig_Has5GBuffers()
        {
            Assert.AreEqual(5, _pcConfig.GBufferCount);
        }

        [Test]
        public void MobileConfig_Has3GBuffers()
        {
            Assert.AreEqual(3, _mobileConfig.GBufferCount);
        }

        #endregion

        #region PC GBuffer Formats

        [Test]
        public void PCConfig_GBuffer0_IsSRGB()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_SRGB, _pcConfig.GetGBufferFormat(0),
                "GBuffer0 (BaseColor) should be sRGB for correct color space handling");
        }

        [Test]
        public void PCConfig_GBuffer1_IsUNorm()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_UNorm, _pcConfig.GetGBufferFormat(1),
                "GBuffer1 (Normal+Smoothness+Metallic) should be UNorm");
        }

        [Test]
        public void PCConfig_GBuffer2_IsUNorm()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_UNorm, _pcConfig.GetGBufferFormat(2),
                "GBuffer2 (Specular+AO+CustomData) should be UNorm");
        }

        [Test]
        public void PCConfig_GBuffer3_IsHDR()
        {
            Assert.AreEqual(GraphicsFormat.B10G11R11_UFloatPack32, _pcConfig.GetGBufferFormat(3),
                "GBuffer3 (Emissive) should be B10G11R11 for HDR values");
        }

        [Test]
        public void PCConfig_GBuffer4_IsUNorm()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_UNorm, _pcConfig.GetGBufferFormat(4),
                "GBuffer4 (CustomData extension) should be UNorm");
        }

        #endregion

        #region Mobile GBuffer Formats

        [Test]
        public void MobileConfig_GBuffer0_IsSRGB()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_SRGB, _mobileConfig.GetGBufferFormat(0),
                "Mobile GBuffer0 should match PC GBuffer0 format");
        }

        [Test]
        public void MobileConfig_GBuffer1_IsUNorm()
        {
            Assert.AreEqual(GraphicsFormat.R8G8B8A8_UNorm, _mobileConfig.GetGBufferFormat(1),
                "Mobile GBuffer1 should match PC GBuffer1 format");
        }

        [Test]
        public void MobileConfig_GBuffer2_IsHDR()
        {
            Assert.AreEqual(GraphicsFormat.B10G11R11_UFloatPack32, _mobileConfig.GetGBufferFormat(2),
                "Mobile GBuffer2 (Emissive/GI) should be HDR");
        }

        #endregion

        #region Cross-Platform Consistency

        [Test]
        public void GBuffer0Format_ConsistentAcrossPlatforms()
        {
            Assert.AreEqual(_pcConfig.GetGBufferFormat(0), _mobileConfig.GetGBufferFormat(0),
                "GBuffer0 format should be consistent across PC and Mobile");
        }

        [Test]
        public void GBuffer1Format_ConsistentAcrossPlatforms()
        {
            Assert.AreEqual(_pcConfig.GetGBufferFormat(1), _mobileConfig.GetGBufferFormat(1),
                "GBuffer1 format should be consistent across PC and Mobile");
        }

        #endregion

        #region Default Values

        [Test]
        public void DefaultConfig_IsPC()
        {
            var config = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            Assert.AreEqual(CustomDeferredConfig.PlatformProfile.PC, config.Platform);
            Object.DestroyImmediate(config);
        }

        [Test]
        public void DefaultConfig_DebugViewDisabled()
        {
            var config = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            Assert.IsFalse(config.EnableDebugView);
            Object.DestroyImmediate(config);
        }

        [Test]
        public void DefaultConfig_DebugGBufferIndexIsZero()
        {
            var config = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            Assert.AreEqual(0, config.DebugGBufferIndex);
            Object.DestroyImmediate(config);
        }

        #endregion
    }
}
#endif
