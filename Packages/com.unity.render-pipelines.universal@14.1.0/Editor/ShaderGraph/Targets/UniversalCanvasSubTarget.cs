using UnityEditor.ShaderGraph;
using UnityEngine;
using UnityEditor.Rendering.Canvas.ShaderGraph;
using System;
using UnityEngine.UIElements;

namespace UnityEditor.Rendering.Universal.ShaderGraph
{
    static class Constants
    {
        public static readonly GUID SourceCodeGuid = new GUID("f7075c3a804b49bf86535f6f86615132");
        public const string CanvasPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/CanvasPass.hlsl";
    }

    /// <summary>
    /// SubTarget for Universal Render Pipeline Canvas shaders.
    /// </summary>
    class UniversalCanvasSubTarget : CanvasSubTarget<UniversalTarget>
    {
        /// <summary>
        /// The display name for this subtarget.
        /// </summary>
        private const string DisplayName = "Canvas";

        // Cached target reference to avoid repeated casting
        private UniversalTarget _universalTarget;
        private CanvasData _cachedCanvasData;

        // Static readonly collections to avoid repeated object creation
        private static readonly DefineCollection s_EmptyDefineCollection = new DefineCollection();
        private static readonly KeywordCollection s_EmptyKeywordCollection = new KeywordCollection();

        /// <summary>
        /// Cached include collection for post-graph includes.
        /// </summary>
        private static readonly IncludeCollection s_PostgraphIncludes = new IncludeCollection
        {
            { Constants.CanvasPass, IncludeLocation.Postgraph },
        };

        /// <summary>
        /// Cached include collection for pre-graph includes.
        /// </summary>
        private static readonly IncludeCollection s_PregraphIncludes = new IncludeCollection
        {
            { CoreIncludes.CorePregraph },
            { CanvasConstants.kInstancing, IncludeLocation.Pregraph },
            { CoreIncludes.ShaderGraphPregraph },
        };

        /// <summary>
        /// Initializes a new instance of the <see cref="UniversalCanvasSubTarget"/> class.
        /// </summary>
        public UniversalCanvasSubTarget()
        {
            displayName = DisplayName;
        }

        // Cache the UniversalTarget reference - optimized to avoid repeated casting
        private UniversalTarget universalTarget 
        {
            get
            {
                if (_universalTarget == null && target is UniversalTarget universal)
                {
                    _universalTarget = universal;
                }
                return _universalTarget;
            }
        }

        // Cache CanvasData reference to avoid repeated property access
        private CanvasData cachedCanvasData
        {
            get
            {
                if (_cachedCanvasData == null)
                {
                    _cachedCanvasData = canvasData;
                }
                return _cachedCanvasData;
            }
        }

        /// <inheritdoc/>
        public override bool IsActive() => true;

        /// <inheritdoc/>
        public override object saveContext => null;

        /// <inheritdoc/>
        protected override string pipelineTag => UniversalTarget.kPipelineTag;

        /// <inheritdoc/>
        protected override GUID sourceCodeGuid => Constants.SourceCodeGuid;

        /// <inheritdoc/>
        protected override string canvasPassInclude => Constants.CanvasPass;

        /// <inheritdoc/>
        public override void Setup(ref TargetSetupContext context)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));

            // Setup base functionality
            base.Setup(ref context);
            
            // Add source code dependency with validation
            if (Constants.SourceCodeGuid != default(GUID))
            {
                context.AddAssetDependency(Constants.SourceCodeGuid, AssetCollection.Flags.SourceDependency);
            }
        }

        /// <summary>
        /// Gets the collection of shader includes that should be added after the graph is processed.
        /// </summary>
        protected override IncludeCollection postgraphIncludes => s_PostgraphIncludes;

        /// <summary>
        /// Gets the collection of shader includes that should be added before the graph is processed.
        /// </summary>
        protected override IncludeCollection pregraphIncludes => s_PregraphIncludes;

        /// <inheritdoc/>
        public override void GetActiveBlocks(ref TargetActiveBlockContext context)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            base.GetActiveBlocks(ref context);
            if (IsAlphaClipEnabled)
            {
                context.AddBlock(BlockFields.SurfaceDescription.AlphaClipThreshold, true);
            }
        }

        /// <inheritdoc/>
        protected override DefineCollection GetAdditionalDefines()
        {
            var baseDefines = base.GetAdditionalDefines();
            var defineCollection = new DefineCollection(baseDefines); // clone
            if (IsAlphaClipEnabled)
            {
                defineCollection.Add(CoreKeywordDescriptors.AlphaTestOn, 1);
            }
            return defineCollection;
        }

        /// <inheritdoc/>
        public override void CollectShaderProperties(PropertyCollector collector, GenerationMode generationMode)
        {
            if (collector == null)
                throw new ArgumentNullException(nameof(collector));
            base.CollectShaderProperties(collector, generationMode);
            if (IsAlphaClipEnabled)
                collector.AddShaderProperty(CanvasProperties.AlphaTest);
        }

        /// <inheritdoc/>
        public override void GetFields(ref TargetFieldContext context)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            base.GetFields(ref context);
            if (IsAlphaClipEnabled)
            {
                context.AddField(Fields.AlphaTest);
            }
        }

        // Cleanup method to clear cached references
        public void ClearCachedReferences()
        {
            _universalTarget = null;
            _cachedCanvasData = null;
        }
    }
} 