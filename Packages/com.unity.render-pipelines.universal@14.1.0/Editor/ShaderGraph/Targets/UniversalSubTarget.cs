using UnityEngine;
using UnityEditor.ShaderGraph;
using static Unity.Rendering.Universal.ShaderUtils;
using UnityEditor.ShaderGraph.Internal;
using System;
using UnityEngine.Rendering;


#if HAS_VFX_GRAPH
using UnityEditor.VFX;
#endif

namespace UnityEditor.Rendering.Universal.ShaderGraph
{
    abstract class UniversalSubTarget : SubTarget<UniversalTarget>, IHasMetadata
#if HAS_VFX_GRAPH
        , IRequireVFXContext
#endif
    {
        static readonly GUID kSourceCodeGuid = new GUID("92228d45c1ff66740bfa9e6d97f7e280");  // UniversalSubTarget.cs

        public static readonly Color foldoutColor = new Color(0.25f, 0.25f, 0.25f, 1);
        public static readonly Color borderColor = new Color(0.222f, 0.222f, 0.222f, 1);
        public readonly static Color customPassFoldoutColor = new Color(0.325f, 0.325f, 0.325f);
        public static readonly float folderBorderTopWidth = 1.5f;
        public static readonly int maximumCustomPasses = 15;

        internal class StencilStatus
        {
            public bool overrideStencilState = false;
            public int stencilReference = 0;
            public int stencilReadMask = 0;
            public int stencilWriteMask = 0;
            public CompareFunction stencilCompareFunction = CompareFunction.Always;
            public StencilOp passOperation = StencilOp.Keep;
            public StencilOp failOperation = StencilOp.Keep;
            public StencilOp zFailOperation = StencilOp.Keep;
        }
        public class CustomPassFoldoutControl
        {
            public bool PassFoldout;
            public TargetPropertyGUIFoldout PassController;
            public CustomPassFoldoutControl(bool foldout, int index)
            {
                PassFoldout = foldout;
                PassController = new TargetPropertyGUIFoldout()
                {
                    text = "Custom Pass " + (index + 1).ToString(),
                    value = PassFoldout,
                    style = { backgroundColor = customPassFoldoutColor, borderTopColor = borderColor, borderTopWidth = folderBorderTopWidth },
                    name = "Custom Pass " + (index + 1).ToString() + " Foldout",
                };
            }
        }
        public enum CustomPassType
        {
            Unlit = 0,
            Lit = 1
        }
        [Serializable]
        public class CustomPassData
        {
            public string LightModeTags;
            public RenderFace PassRenderFace;
            public CustomPassType PassType;
            public SurfaceType SurfaceType;
            public AlphaMode BlendMode;
            public ZWriteControl ZWrite;
            public UniversalTarget.ZTestModeForUI ZTest;
            public bool AlphaClip;
            public bool overrideStencilState;
            public int stencilReference;
            public int stencilReadMask;
            public int stencilWriteMask;
            public CompareFunction stencilCompareFunction;
            public StencilOp passOperation;
            public StencilOp failOperation;
            public StencilOp zFailOperation;

            public CustomPassData()
            {
                PassRenderFace = RenderFace.Front;
                SurfaceType = SurfaceType.Opaque;
                PassType = CustomPassType.Unlit;
                ZWrite = ZWriteControl.Auto;
                ZTest = UniversalTarget.ZTestModeForUI.LEqual;
                AlphaClip = false;
                overrideStencilState = false;
                stencilReference = 0;
                stencilReadMask = 0;
                stencilWriteMask = 0;
                stencilCompareFunction = CompareFunction.Always;
                passOperation = StencilOp.Keep;
                failOperation = StencilOp.Keep;
                zFailOperation = StencilOp.Keep;
            }
            public CustomPassData(int index)
            {
                PassRenderFace = RenderFace.Front;
                SurfaceType = SurfaceType.Opaque;
                PassType = CustomPassType.Unlit;
                ZWrite = ZWriteControl.Auto;
                ZTest = UniversalTarget.ZTestModeForUI.LEqual;
                AlphaClip = false;
                LightModeTags = "CustomPass" + index.ToString();
                overrideStencilState = false;
                stencilReference = 0;
                stencilReadMask = 0;
                stencilWriteMask = 0;
                stencilCompareFunction = CompareFunction.Always;
                passOperation = StencilOp.Keep;
                failOperation = StencilOp.Keep;
                zFailOperation = StencilOp.Keep;
            }
        }

        public override void Setup(ref TargetSetupContext context)
        {
            context.AddAssetDependency(kSourceCodeGuid, AssetCollection.Flags.SourceDependency);
        }

        protected abstract ShaderID shaderID { get; }

#if HAS_VFX_GRAPH
        // VFX Properties
        VFXContext m_ContextVFX = null;
        VFXContextCompiledData m_ContextDataVFX;
        protected bool TargetsVFX() => m_ContextVFX != null;

        public void ConfigureContextData(VFXContext context, VFXContextCompiledData data)
        {
            m_ContextVFX = context;
            m_ContextDataVFX = data;
        }

#endif

        protected SubShaderDescriptor PostProcessSubShader(SubShaderDescriptor subShaderDescriptor)
        {
#if HAS_VFX_GRAPH
            if (TargetsVFX())
                return VFXSubTarget.PostProcessSubShader(subShaderDescriptor, m_ContextVFX, m_ContextDataVFX);
#endif
            return subShaderDescriptor;
        }

        public override void GetFields(ref TargetFieldContext context)
        {
#if HAS_VFX_GRAPH
            if (TargetsVFX())
                VFXSubTarget.GetFields(ref context, m_ContextVFX);
#endif
        }

        public virtual string identifier => GetType().Name;
        public virtual ScriptableObject GetMetadataObject(GraphDataReadOnly graphData)
        {
            var urpMetadata = ScriptableObject.CreateInstance<UniversalMetadata>();
            urpMetadata.shaderID = shaderID;
            urpMetadata.alphaMode = target.alphaMode;
            urpMetadata.isVFXCompatible = graphData.IsVFXCompatible();

            if (shaderID != ShaderID.SG_SpriteLit && shaderID != ShaderID.SG_SpriteUnlit)
            {
                urpMetadata.allowMaterialOverride = target.allowMaterialOverride;
                urpMetadata.surfaceType = target.surfaceType;
                urpMetadata.castShadows = target.castShadows;
                urpMetadata.modifiedVertexInMotionVector = target.additionalMotionVectorMode != AdditionalMotionVectorMode.None || graphData.AnyVertexAnimationActive();
            }
            else
            {
                //Ignore unsupported settings in SpriteUnlit/SpriteLit
                urpMetadata.allowMaterialOverride = false;
                urpMetadata.surfaceType = SurfaceType.Transparent;
                urpMetadata.castShadows = false;
                urpMetadata.modifiedVertexInMotionVector = false;
            }

            return urpMetadata;
        }

        private int lastMaterialNeedsUpdateHash = 0;
        protected virtual int ComputeMaterialNeedsUpdateHash() => 0;
        public override object saveContext
        {
            get
            {
                int hash = ComputeMaterialNeedsUpdateHash();
                bool needsUpdate = hash != lastMaterialNeedsUpdateHash;
                if (needsUpdate)
                    lastMaterialNeedsUpdateHash = hash;

                return new UniversalShaderGraphSaveContext { updateMaterials = needsUpdate };
            }
        }
        public void AddFoldoutController(string text, string name, int indentLevel, ref TargetPropertyGUIFoldout foldoutController, ref bool foldout)
        {
            foldoutController = new TargetPropertyGUIFoldout()
            {
                text = text,
                value = foldout,
                style = { backgroundColor = foldoutColor, borderTopColor = borderColor, borderTopWidth = folderBorderTopWidth },
                name = name
            };
            foldoutController.ApplyIndent(indentLevel);
        }

        public static void AddCustomPassControls(ref PassDescriptor result, CustomPassData customPassData, bool blendModePreserveSpecular = false)
        {
            if (customPassData.ZWrite == ZWriteControl.Auto)
            {
                if (customPassData.SurfaceType == SurfaceType.Opaque)
                    result.renderStates.Add(RenderState.ZWrite(ZWrite.On));
                else
                    result.renderStates.Add(RenderState.ZWrite(ZWrite.Off));
            }
            else if (customPassData.ZWrite == ZWriteControl.ForceEnabled)
                result.renderStates.Add(RenderState.ZWrite(ZWrite.On));
            else
                result.renderStates.Add(RenderState.ZWrite(ZWrite.Off));
            result.renderStates.Add(RenderState.ZTest(customPassData.ZTest.ToString()));
            result.renderStates.Add(RenderState.Cull(CoreRenderStates.RenderFaceToCull(customPassData.PassRenderFace)));
            if (customPassData.AlphaClip && (customPassData.SurfaceType == SurfaceType.Opaque))
                result.renderStates.Add(RenderState.AlphaToMask("On"));

            if (customPassData.SurfaceType == SurfaceType.Opaque)
            {
                result.renderStates.Add(RenderState.Blend(Blend.One, Blend.Zero));
                if (customPassData.AlphaClip)
                    result.defines.Add(CoreKeywordDescriptors.AlphaTestOn, 1);
            }
            else
            {
                // Lift alpha multiply from ROP to shader in preserve spec for different diffuse and specular blends.
                Blend blendSrcRGB = blendModePreserveSpecular ? Blend.One : Blend.SrcAlpha;
                switch (customPassData.BlendMode)
                {
                    case AlphaMode.Alpha:
                        result.renderStates.Add(RenderState.Blend(Blend.SrcAlpha, Blend.OneMinusSrcAlpha, Blend.One, Blend.OneMinusSrcAlpha));
                        break;
                    case AlphaMode.Premultiply:
                        result.renderStates.Add(RenderState.Blend(Blend.One, Blend.OneMinusSrcAlpha, Blend.One, Blend.OneMinusSrcAlpha));
                        break;
                    case AlphaMode.Additive:
                        result.renderStates.Add(RenderState.Blend(blendSrcRGB, Blend.One, Blend.One, Blend.One));
                        break;
                    case AlphaMode.Multiply:
                        result.renderStates.Add(RenderState.Blend(Blend.DstColor, Blend.Zero, Blend.Zero, Blend.One)); // Multiply RGB only, keep A
                        break;
                }
                result.defines.Add(CoreKeywordDescriptors.SurfaceTypeTransparent, 1);
                if ((customPassData.BlendMode == AlphaMode.Alpha || customPassData.BlendMode == AlphaMode.Additive) && blendModePreserveSpecular)
                    result.defines.Add(CoreKeywordDescriptors.AlphaPremultiplyOn, 1);
                else if (customPassData.BlendMode == AlphaMode.Multiply)
                    result.defines.Add(CoreKeywordDescriptors.AlphaModulateOn, 1);
            }
        }
        internal static void AddStencilStatusControl(ref PassDescriptor result, StencilStatus stencilState)
        {
            if (stencilState.overrideStencilState)
            {
                result.renderStates.Add(RenderState.Stencil(new StencilDescriptor
                {
                    Ref = stencilState.stencilReference.ToString(),
                    ReadMask = stencilState.stencilReadMask.ToString(),
                    WriteMask = stencilState.stencilWriteMask.ToString(),
                    Comp = CompareFunctionToStencilString(stencilState.stencilCompareFunction),
                    Pass = StencilOpToStencilString(stencilState.passOperation),
                    Fail = StencilOpToStencilString(stencilState.failOperation),
                    ZFail = StencilOpToStencilString(stencilState.zFailOperation)
                }));
            }
        }
        internal static string CompareFunctionToStencilString(CompareFunction compare)
        {
            switch (compare)
            {
                case CompareFunction.Never: return "Never";
                case CompareFunction.Equal: return "Equal";
                case CompareFunction.NotEqual: return "NotEqual";
                case CompareFunction.Greater: return "Greater";
                case CompareFunction.Less: return "Less";
                case CompareFunction.GreaterEqual: return "GEqual";
                case CompareFunction.LessEqual: return "LEqual";
                case CompareFunction.Always: return "Always";
                default: return "Always";
            };
        }

        internal static string StencilOpToStencilString(StencilOp op)
        {
            switch (op)
            {
                case StencilOp.Keep: return "Keep";
                case StencilOp.Zero: return "Zero";
                case StencilOp.Replace: return "Replace";
                case StencilOp.IncrementSaturate: return "IncrSat";
                case StencilOp.DecrementSaturate: return "DecrSat";
                case StencilOp.Invert: return "Invert";
                case StencilOp.IncrementWrap: return "IncrWrap";
                case StencilOp.DecrementWrap: return "DecrWrap";
                default: return "Keep";
            };
        }
    }

    internal static class SubShaderUtils
    {
        internal static void AddFloatProperty(this PropertyCollector collector, string referenceName, float defaultValue, HLSLDeclaration declarationType = HLSLDeclaration.DoNotDeclare)
        {
            collector.AddShaderProperty(new Vector1ShaderProperty
            {
                floatType = FloatType.Default,
                hidden = true,
                overrideHLSLDeclaration = true,
                hlslDeclarationOverride = declarationType,
                value = defaultValue,
                displayName = referenceName,
                overrideReferenceName = referenceName,
            });
        }

        internal static void AddToggleProperty(this PropertyCollector collector, string referenceName, bool defaultValue, HLSLDeclaration declarationType = HLSLDeclaration.DoNotDeclare)
        {
            collector.AddShaderProperty(new BooleanShaderProperty
            {
                value = defaultValue,
                hidden = true,
                overrideHLSLDeclaration = true,
                hlslDeclarationOverride = declarationType,
                displayName = referenceName,
                overrideReferenceName = referenceName,
            });
        }

        // Overloads to do inline PassDescriptor modifications
        // NOTE: param order should match PassDescriptor field order for consistency
        #region PassVariant
        internal static PassDescriptor PassVariant(in PassDescriptor source, PragmaCollection pragmas)
        {
            var result = source;
            result.pragmas = pragmas;
            return result;
        }

        #endregion
    }
}
