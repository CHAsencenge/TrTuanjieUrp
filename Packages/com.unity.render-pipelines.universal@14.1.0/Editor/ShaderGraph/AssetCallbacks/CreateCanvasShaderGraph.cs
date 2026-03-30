using System;
using UnityEditor.ShaderGraph;
using UnityEngine.Rendering;
using UnityEditor.Rendering.Fullscreen.ShaderGraph;

namespace UnityEditor.Rendering.Universal.ShaderGraph
{
    static class CreateCanvasShaderGraph
    {
        /// <summary>
        /// Create lightweight Canvas Shader Graph
        /// Includes basic functionality such as base color, emission, alpha, and alpha clip threshold
        /// </summary>
        [MenuItem("Assets/Create/Shader Graph/URP/Canvas Shader Graph", priority = CoreUtils.Sections.section5 + CoreUtils.Priorities.assetsCreateShaderMenuPriority)]
        public static void CreateLiteCanvasGraph()
        {
            // Create and configure Universal render pipeline target
            var liteTarget = CreateUniversalTarget();
            liteTarget.TrySetActiveSubTarget(typeof(UniversalCanvasSubTarget));

            // Define base block descriptors
            var liteBlockDescriptors = GetBaseBlockDescriptors();

            // Create new Shader Graph
            GraphUtil.CreateNewGraphWithOutputs(new[] { liteTarget }, liteBlockDescriptors);
        }

        /// <summary>
        /// Create Universal render pipeline target instance
        /// </summary>
        private static UniversalTarget CreateUniversalTarget()
        {
            return (UniversalTarget)Activator.CreateInstance(typeof(UniversalTarget));
        }

        /// <summary>
        /// Get base block descriptors array
        /// </summary>
        private static BlockFieldDescriptor[] GetBaseBlockDescriptors()
        {
            return new[]
            {
                BlockFields.SurfaceDescription.BaseColor,      // Base color
                BlockFields.SurfaceDescription.Emission,       // Emission
                BlockFields.SurfaceDescription.Alpha,          // Alpha
                BlockFields.SurfaceDescription.AlphaClipThreshold, // Alpha clip threshold
            };
        }
    }
}
