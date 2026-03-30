#if ENABLE_UNIT_TESTS
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.Rendering.Universal;
using Game.Rendering;

namespace Game.Tests.Runtime
{
    /// <summary>
    /// Runtime integration tests for the custom deferred rendering pipeline.
    /// Validates that the pipeline components can be created and configured correctly.
    /// </summary>
    [TestFixture]
    public class DeferredPipelineIntegrationTests
    {
        [Test]
        public void CustomDeferredConfig_CanBeCreatedAtRuntime()
        {
            var config = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            Assert.IsNotNull(config);
            Assert.Greater(config.GBufferCount, 0);
            Object.DestroyImmediate(config);
        }

        [Test]
        public void CustomGBufferPass_CanBeConstructed()
        {
            var config = ScriptableObject.CreateInstance<CustomDeferredConfig>();
            var pass = new CustomGBufferPass(config);
            Assert.IsNotNull(pass);
            Object.DestroyImmediate(config);
        }

        [Test]
        public void DeferredLightingShader_Exists()
        {
            var shader = Shader.Find("Hidden/Custom/DeferredLighting");
            Assert.IsNotNull(shader, "Deferred lighting shader should be findable by name");
        }

        [Test]
        public void GBufferShader_Exists()
        {
            var shader = Shader.Find("Custom/DeferredGBuffer");
            Assert.IsNotNull(shader, "GBuffer shader should be findable by name");
        }

        [Test]
        public void CustomDeferredRendererFeature_CanBeCreated()
        {
            var feature = ScriptableObject.CreateInstance<CustomDeferredRendererFeature>();
            Assert.IsNotNull(feature);
            Object.DestroyImmediate(feature);
        }

        [Test]
        public void GBufferMaterial_CanBeCreated()
        {
            var shader = Shader.Find("Custom/DeferredGBuffer");
            if (shader == null)
            {
                Assert.Inconclusive("GBuffer shader not available in this context");
                return;
            }

            var material = new Material(shader);
            Assert.IsNotNull(material);

            // Verify default property values
            Assert.AreEqual(0, material.GetInt("_ShadingModelId"));
            Assert.AreEqual(0, material.GetInt("_MaterialFlags"));

            Object.DestroyImmediate(material);
        }
    }
}
#endif
