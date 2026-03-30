using System;
using System.Linq;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor.ShaderGraph;
using UnityEditor.UIElements;
using UnityEngine.UIElements;
using UnityEditor.ShaderGraph.Legacy;
using UnityEngine.Assertions;
using static UnityEditor.Rendering.Universal.ShaderGraph.SubShaderUtils;
using UnityEngine.Rendering.Universal;
using static Unity.Rendering.Universal.ShaderUtils;
using UnityEditor.ShaderGraph.Drawing;
using UnityEditor.Rendering.Universal.Analytics;
using static UnityEditor.ShaderGraph.Drawing.Inspector.PropertyDrawers.GraphDataPropertyDrawer;
using UnityEditor.Rendering.Fullscreen.ShaderGraph;
using UnityEngine.Rendering;

namespace UnityEditor.Rendering.Universal.ShaderGraph
{
    sealed class UniversalScalableLitSubTarget : UniversalSubTarget, ILegacyTarget
    {
        static readonly GUID kSourceCodeGuid = new GUID("e47abd678c01c0c48a0bd20811a82ff2"); // UniversalComplexLitSubTarget.cs

        public override int latestVersion => 3;

        [SerializeField]
        WorkflowMode m_WorkflowMode = WorkflowMode.Metallic;

        [SerializeField]
        NormalDropOffSpace m_NormalDropOffSpace = NormalDropOffSpace.Tangent;

        [SerializeField]
        DiffuseModel m_DiffuseModel = DiffuseModel.Low;

        [SerializeField]
        SpecularModel m_SpecularModel = SpecularModel.Medium;

        [SerializeField]
        bool m_GI = true;

        [SerializeField]
        bool m_CustomLighting = false;

        [SerializeField]
        bool m_BlendModePreserveSpecular = true;

        [SerializeField]
        bool m_UsePreIntegratedFDG = false;

        [SerializeField]
        List<string> m_RemovedVariants = new List<string>();

        [SerializeField]
        List<string> m_RemovedPasses = new List<string>();

        [SerializeField]
        List<string> m_Features = new List<string>();

        public UniversalScalableLitSubTarget()
        {
            displayName = "Scalable Lit";
        }

        protected override ShaderID shaderID => ShaderID.SG_ScalableLit;

        public WorkflowMode workflowMode
        {
            get => m_WorkflowMode;
            set => m_WorkflowMode = value;
        }

        public NormalDropOffSpace normalDropOffSpace
        {
            get => m_NormalDropOffSpace;
            set => m_NormalDropOffSpace = value;
        }

        public DiffuseModel diffuseModel
        {
            get => m_DiffuseModel;
            set => m_DiffuseModel = value;
        }

        public SpecularModel specularModel
        {
            get => m_SpecularModel;
            set => m_SpecularModel = value;
        }
        public bool gi
        {
            get => m_GI;
            set => m_GI = value;
        }
        public bool customLighting
        {
            get => m_CustomLighting;
            set => m_CustomLighting = value;
        }

        public bool usePreIntegratedFDG
        {
            get => m_UsePreIntegratedFDG;
            set => m_UsePreIntegratedFDG = value;
        }

        private bool complexLit
        {
            get
            {
                // Rules for switching to ComplexLit with forward only pass
                return usePreIntegratedFDG || HasFeatureType(ScalableLitFeatureTypeMask.ClearCoat) || HasFeatureType(ScalableLitFeatureTypeMask.ThinFilm) || HasFeatureType(ScalableLitFeatureTypeMask.DiffractionGratings) || specularModel != SpecularModel.Medium || diffuseModel != DiffuseModel.Low || !gi || customLighting; // && <complex feature>
            }
        }

        public bool blendModePreserveSpecular
        {
            get => m_BlendModePreserveSpecular;
            set => m_BlendModePreserveSpecular = value;
        }

        public List<string> removedVariants
        {
            get => m_RemovedVariants;
            set => m_RemovedVariants = value;
        }
        public List<string> removedPasses
        {
            get => m_RemovedPasses;
            set => m_RemovedPasses = value;
        }

        [Obsolete("Use feature mask instead", false)]
        public List<string> features
        {
            get => m_Features;
            set => m_Features = value;
        }
        [SerializeField]
        public List<bool> keywordsStatus = Enumerable.Repeat(true, KeywordName.keywordDic.Count()).ToList();
        [SerializeField]
        public List<bool> passStatus = Enumerable.Repeat(true, PassName.passDic.Count()).ToList();
        [SerializeField]
        public List<bool> featureStatus = Enumerable.Repeat(false, FeatureName.featureDic.Count()).ToList();

        [SerializeField]
        public int customPassCount = 0;

        // Foldout
        public TargetPropertyGUIFoldout shadingFeaturesController;
        public bool shadingFeatureFoldout = false;

        public TargetPropertyGUIFoldout surfaceOptionsController;
        public bool surfaceOptionsFoldout = false;

        public TargetPropertyGUIFoldout shadingQualityController;
        public bool shadingQualityFoldout = false;

        public TargetPropertyGUIFoldout passesController;
        public bool passesFoldout = false;

        public TargetPropertyGUIFoldout variantsController;
        public bool variantsFoldout = false;

        public TargetPropertyGUIFoldout customPassController;
        public bool customPassFoldout = false;

        [SerializeField]
        public List<CustomPassData> customPassData = new List<CustomPassData>();
        public List<CustomPassFoldoutControl> customPassFoldoutControls = new List<CustomPassFoldoutControl>();

        public override bool IsActive() => true;

        // featuer mask
        [Flags]
        public enum ScalableLitFeatureTypeMask
        {
            ClearCoat = 1 << 2,
            ThinFilm = 1 << 3,
            DiffractionGratings = 1 << 4,
            Anisotropy = 1 << 5,
            CustomIndirectDiffuse = 1 << 6,
            CustomIndirectSpecular = 1 << 7
        }

        [SerializeField]
        ScalableLitFeatureTypeMask m_FeatureTypeMask;
        public ScalableLitFeatureTypeMask featureTypeMask
        {
            get => m_FeatureTypeMask;
            set
            {
                m_FeatureTypeMask = value;
            }
        }
        public bool HasFeatureType(ScalableLitFeatureTypeMask featureType) => (m_FeatureTypeMask & featureType) != 0;
        [SerializeField]
        bool m_AllowFeatureOverride = false;
        public bool allowFeatureOverride
        {
            get => m_AllowFeatureOverride;
            set
            {
                m_AllowFeatureOverride = value;
            }
        }

        private ScalableLitTargetParams m_subTargetParams;

        public override void Setup(ref TargetSetupContext context)
        {
            context.AddAssetDependency(kSourceCodeGuid, AssetCollection.Flags.SourceDependency);
            base.Setup(ref context);

            var universalRPType = typeof(UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset);
            if (!context.HasCustomEditorForRenderPipeline(universalRPType))
            {
                var gui = typeof(ShaderGraphScalableLitGUI);
#if HAS_VFX_GRAPH
                if (TargetsVFX())
                    gui = typeof(VFXShaderGraphLitGUI);
#endif
                context.AddCustomEditorForRenderPipeline(gui.FullName, universalRPType);
            }


            // init params
            if (keywordsStatus.Count() != KeywordName.keywordDic.Count())
            {
                List<bool> tempKeywordStatus = Enumerable.Repeat(true, KeywordName.keywordDic.Count()).ToList();
                List<string> tempRemovedKeywords = new List<string>();
                for (int i = 0; i < removedVariants.Count(); i++)
                {
                    if (KeywordName.keywordDic.ContainsKey(removedVariants[i]))
                    {
                        tempRemovedKeywords.Add(removedVariants[i]);
                        tempKeywordStatus[KeywordName.GetKeywordID(removedVariants[i])] = false;
                    }
                }
                removedVariants = tempRemovedKeywords;
                keywordsStatus = tempKeywordStatus;
            }

            if (passStatus.Count() != PassName.passDic.Count())
            {
                List<bool> tempPassStatus = Enumerable.Repeat(true, PassName.passDic.Count()).ToList();
                List<string> tempRemovedPasses = new List<string>();
                for (int i = 0; i < removedPasses.Count(); i++)
                {
                    if (PassName.passDic.ContainsKey(removedPasses[i]))
                    {
                        tempRemovedPasses.Add(removedPasses[i]);
                        tempPassStatus[PassName.GetPassID(removedPasses[i])] = false;
                    }
                }
                removedPasses = tempRemovedPasses;
                passStatus = tempPassStatus;
            }
            m_subTargetParams.diffuseModel = diffuseModel;
            m_subTargetParams.specularModel = specularModel;
            m_subTargetParams.GI = gi;
            m_subTargetParams.CustomLighting = customLighting;
            m_subTargetParams.passStatus = passStatus;
            m_subTargetParams.keywordsStatus = keywordsStatus;
            m_subTargetParams.stencilStatus = new StencilStatus
            {
                overrideStencilState = target.overrideStencilState,
                stencilReference = target.stencilReference,
                stencilReadMask = target.stencilReadMask,
                stencilWriteMask = target.stencilWriteMask,
                stencilCompareFunction = target.stencilCompareFunction,
                passOperation = target.passOperation,
                failOperation = target.failOperation,
                zFailOperation = target.zFailOperation
            };
            m_subTargetParams.featureTypeMask = featureTypeMask;
            m_subTargetParams.AllowFeatureOverride = allowFeatureOverride;
            m_subTargetParams.UsePreIntegratedFDG = usePreIntegratedFDG;
            m_subTargetParams.customPassData = customPassData;
            context.AddSubShader(PostProcessSubShader(SubShaders.LitSubShader(target, m_subTargetParams, workflowMode, target.renderType, target.renderQueue, target.disableBatching, complexLit, blendModePreserveSpecular)));
        }
        public override void ProcessPreviewMaterial(Material material)
        {
            if (target.allowMaterialOverride)
            {
                // copy our target's default settings into the material
                // (technically not necessary since we are always recreating the material from the shader each time,
                // which will pull over the defaults from the shader definition)
                // but if that ever changes, this will ensure the defaults are set
                material.SetFloat(Property.SpecularWorkflowMode, (float)workflowMode);
                material.SetFloat(Property.CastShadows, target.castShadows ? 1.0f : 0.0f);
                material.SetFloat(Property.ReceiveShadows, target.receiveShadows ? 1.0f : 0.0f);
                material.SetFloat(Property.SurfaceType, (float)target.surfaceType);
                material.SetFloat(Property.BlendMode, (float)target.alphaMode);
                material.SetFloat(Property.AlphaClip, target.alphaClip ? 1.0f : 0.0f);
                material.SetFloat(Property.CullMode, (int)target.renderFace);
                material.SetFloat(Property.ZWriteControl, (float)target.zWriteControl);
                material.SetFloat(Property.ZTest, (float)target.zTestMode);
            }

            // We always need these properties regardless of whether the material is allowed to override
            // Queue control & offset enable correct automatic render queue behavior
            // Control == 0 is automatic, 1 is user-specified render queue
            material.SetFloat(Property.QueueOffset, 0.0f);
            material.SetFloat(Property.QueueControl, (float)BaseShaderGUI.QueueControl.Auto);

            // call the full unlit material setup function
            ShaderGraphScalableLitGUI.UpdateMaterial(material, MaterialUpdateType.CreatedNewMaterial);
        }

        public override void GetFields(ref TargetFieldContext context)
        {
            base.GetFields(ref context);

            var descs = context.blocks.Select(x => x.descriptor);

            // Lit -- always controlled by subtarget
            context.AddField(UniversalFields.NormalDropOffOS, normalDropOffSpace == NormalDropOffSpace.Object);
            context.AddField(UniversalFields.NormalDropOffTS, normalDropOffSpace == NormalDropOffSpace.Tangent);
            context.AddField(UniversalFields.NormalDropOffWS, normalDropOffSpace == NormalDropOffSpace.World);
            context.AddField(UniversalFields.Normal, descs.Contains(BlockFields.SurfaceDescription.NormalOS) ||
                descs.Contains(BlockFields.SurfaceDescription.NormalTS) ||
                descs.Contains(BlockFields.SurfaceDescription.NormalWS));
            // Complex Lit

            // Template Predicates
            //context.AddField(UniversalFields.PredicateClearCoat, clearCoat);
        }

        public override void GetActiveBlocks(ref TargetActiveBlockContext context)
        {
            context.AddBlock(UniversalBlockFields.VertexDescription.MotionVector, target.additionalMotionVectorMode == AdditionalMotionVectorMode.Custom);

            context.AddBlock(BlockFields.SurfaceDescription.Smoothness);
            context.AddBlock(BlockFields.SurfaceDescription.NormalOS, normalDropOffSpace == NormalDropOffSpace.Object);
            context.AddBlock(BlockFields.SurfaceDescription.NormalTS, normalDropOffSpace == NormalDropOffSpace.Tangent);
            context.AddBlock(BlockFields.SurfaceDescription.NormalWS, normalDropOffSpace == NormalDropOffSpace.World);
            context.AddBlock(BlockFields.SurfaceDescription.Emission);
            context.AddBlock(BlockFields.SurfaceDescription.Occlusion);
            // when the surface options are material controlled, we must show all of these blocks
            // when target controlled, we can cull the unnecessary blocks
            context.AddBlock(BlockFields.SurfaceDescription.Specular, (workflowMode == WorkflowMode.Specular) || target.allowMaterialOverride);
            context.AddBlock(BlockFields.SurfaceDescription.Metallic, (workflowMode == WorkflowMode.Metallic) || target.allowMaterialOverride);
            context.AddBlock(BlockFields.SurfaceDescription.Alpha, (target.surfaceType == SurfaceType.Transparent || target.alphaClip) || target.allowMaterialOverride || customPassData.Any(x => x.SurfaceType == SurfaceType.Transparent));
            context.AddBlock(BlockFields.SurfaceDescription.AlphaClipThreshold, (target.alphaClip) || target.allowMaterialOverride || customPassData.Any(x => x.AlphaClip));

            // these features are only valid for forward pass
            if (passStatus[PassName.GetPassID(PassName.forwardPass)])
            {
                context.AddBlock(BlockFields.SurfaceDescription.CoatMask, HasFeatureType(ScalableLitFeatureTypeMask.ClearCoat));
                context.AddBlock(BlockFields.SurfaceDescription.CoatSmoothness, HasFeatureType(ScalableLitFeatureTypeMask.ClearCoat));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.ClearCoatNormal, HasFeatureType(ScalableLitFeatureTypeMask.ClearCoat));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.ThinFilmThickness, HasFeatureType(ScalableLitFeatureTypeMask.ThinFilm));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.ThinFilmMask, HasFeatureType(ScalableLitFeatureTypeMask.ThinFilm));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.SlitsDistance, HasFeatureType(ScalableLitFeatureTypeMask.DiffractionGratings));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.SlitsMask, HasFeatureType(ScalableLitFeatureTypeMask.DiffractionGratings));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.SlitsDirection, HasFeatureType(ScalableLitFeatureTypeMask.DiffractionGratings));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.Anisotropy, specularModel == SpecularModel.High);
                context.AddBlock(UniversalBlockFields.SurfaceDescription.Tangent, specularModel == SpecularModel.High);
                context.AddBlock(UniversalBlockFields.SurfaceDescription.CustomIndirectSpecular, HasFeatureType(ScalableLitFeatureTypeMask.CustomIndirectSpecular));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.IndirectSpecularMask, HasFeatureType(ScalableLitFeatureTypeMask.CustomIndirectSpecular));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.CustomIndirectDiffuse, HasFeatureType(ScalableLitFeatureTypeMask.CustomIndirectDiffuse));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.IndirectDiffuseMask, HasFeatureType(ScalableLitFeatureTypeMask.CustomIndirectDiffuse));
                context.AddBlock(UniversalBlockFields.SurfaceDescription.CustomLighting, customLighting);
                context.AddBlock(UniversalBlockFields.SurfaceDescription.CustomSpecularFDG, usePreIntegratedFDG);
                context.AddBlock(UniversalBlockFields.SurfaceDescription.CustomEnergyCompensation, usePreIntegratedFDG);
            }
        }
        public override void CollectShaderProperties(PropertyCollector collector, GenerationMode generationMode)
        {
            // if using material control, add the material property to control workflow mode
            if (target.allowMaterialOverride)
            {
                collector.AddFloatProperty(Property.SpecularWorkflowMode, (float)workflowMode);
                collector.AddFloatProperty(Property.CastShadows, target.castShadows ? 1.0f : 0.0f);
                collector.AddFloatProperty(Property.ReceiveShadows, target.receiveShadows ? 1.0f : 0.0f);

                // setup properties using the defaults
                collector.AddFloatProperty(Property.SurfaceType, (float)target.surfaceType);
                collector.AddFloatProperty(Property.BlendMode, (float)target.alphaMode);
                collector.AddFloatProperty(Property.AlphaClip, target.alphaClip ? 1.0f : 0.0f);
                collector.AddFloatProperty(Property.BlendModePreserveSpecular, blendModePreserveSpecular ? 1.0f : 0.0f);
                collector.AddFloatProperty(Property.SrcBlend, 1.0f);    // always set by material inspector, ok to have incorrect values here
                collector.AddFloatProperty(Property.DstBlend, 0.0f);    // always set by material inspector, ok to have incorrect values here
                collector.AddToggleProperty(Property.ZWrite, (target.surfaceType == SurfaceType.Opaque));
                collector.AddFloatProperty(Property.ZWriteControl, (float)target.zWriteControl);
                collector.AddFloatProperty(Property.ZTest, (float)target.zTestMode);    // ztest mode is designed to directly pass as ztest
                collector.AddFloatProperty(Property.CullMode, (float)target.renderFace);    // render face enum is designed to directly pass as a cull mode

                bool enableAlphaToMask = (target.alphaClip && (target.surfaceType == SurfaceType.Opaque));
                collector.AddFloatProperty(Property.AlphaToMask, enableAlphaToMask ? 1.0f : 0.0f);
            }

#if UNITY_GPU_DRIVEN_PIPELINE
            if (UnityEngine.Rendering.GraphicsSettings.enableGDRP && !target.allowMaterialOverride)
            {
                collector.AddFloatProperty(Property.CullMode, (float)target.renderFace);
            }
#endif

            if (allowFeatureOverride)
                collector.AddIntProperty(Property.ShadingFeatuers, (int)featureTypeMask);

            // We always need these properties regardless of whether the material is allowed to override other shader properties.
            // Queue control & offset enable correct automatic render queue behavior.  Control == 0 is automatic, 1 is user-specified.
            // We initialize queue control to -1 to indicate to UpdateMaterial that it needs to initialize it properly on the material.
            collector.AddFloatProperty(Property.QueueOffset, 0.0f);
            collector.AddFloatProperty(Property.QueueControl, -1.0f);
        }

        PostTargetSettingsChangedCallback m_postChangeTargetSettingsCallback;
        ChangeGraphDefaultPrecisionCallback m_changeGraphDefaultPrecisionCallback;

        public override int CustomPassCount()
        {
            return customPassCount;
        }
        public override List<int> GetCustomPassType()
        {
            return customPassData.Select(x => (int)x.PassType).ToList();
        }
        public override void GetPropertiesGUI(ref TargetPropertyGUIContext context, Action onChange, Action<String> registerUndo)
        {
            var universalTarget = (target as UniversalTarget);

            #region SurfaceOptions
            AddFoldoutController("Surface Options", "Surface Options Foldout", context.globalIndentLevel, ref surfaceOptionsController, ref surfaceOptionsFoldout);
            surfaceOptionsController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                surfaceOptionsFoldout = !surfaceOptionsFoldout;
                onChange();
            });
            context.Add(surfaceOptionsController);
            if (surfaceOptionsFoldout)
            {
                context.globalIndentLevel++;
                universalTarget.AddDefaultMaterialOverrideGUI(ref context, onChange, registerUndo);

                context.AddProperty("Workflow Mode", new EnumField(WorkflowMode.Metallic) { value = workflowMode }, (evt) =>
                {
                    if (Equals(workflowMode, evt.newValue))
                        return;

                    registerUndo("Change Workflow");
                    workflowMode = (WorkflowMode)evt.newValue;
                    onChange();
                });

                universalTarget.AddDefaultSurfacePropertiesGUI(ref context, onChange, registerUndo, showReceiveShadows: true);
                context.AddProperty("Fragment Normal Space", new EnumField(NormalDropOffSpace.Tangent) { value = normalDropOffSpace }, (evt) =>
                {
                    if (Equals(normalDropOffSpace, evt.newValue))
                        return;

                    registerUndo("Change Fragment Normal Space");
                    normalDropOffSpace = (NormalDropOffSpace)evt.newValue;
                    onChange();
                });
                if (target.surfaceType == SurfaceType.Transparent)
                {
                    if (target.alphaMode == AlphaMode.Alpha || target.alphaMode == AlphaMode.Additive)
                        context.AddProperty("Preserve Specular Lighting", new Toggle() { value = blendModePreserveSpecular }, (evt) =>
                        {
                            if (Equals(blendModePreserveSpecular, evt.newValue))
                                return;

                            registerUndo("Change Preserve Specular");
                            blendModePreserveSpecular = evt.newValue;
                            onChange();
                        });
                }
                context.globalIndentLevel--;
            }
            #endregion

            #region ShadingQuality
            AddFoldoutController("Shading Quality", "Shading Quality Foldout", context.globalIndentLevel, ref shadingQualityController, ref shadingQualityFoldout);
            shadingQualityController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                shadingQualityFoldout = !shadingQualityFoldout;
                onChange();
            });
            context.Add(shadingQualityController);

            if (shadingQualityFoldout)
            {
                context.globalIndentLevel++;

                context.AddProperty("Custom Lighting Block", new Toggle() { value = customLighting }, (evt) =>
                {
                    if (Equals(customLighting, evt.newValue))
                        return;
                    registerUndo("Change Custom Lighting Block");
                    customLighting = evt.newValue;
                    onChange();
                });

                context.AddProperty("Receive Global Illumination", new Toggle() { value = gi }, (evt) =>
                {
                    if (Equals(gi, evt.newValue))
                        return;
                    registerUndo("Change Receive Global Illumination");
                    gi = evt.newValue;
                    onChange();
                });

                context.AddProperty("Custom PreIntegrated FDG", new Toggle() { value = usePreIntegratedFDG }, (evt) =>
                {
                    if (Equals(usePreIntegratedFDG, evt.newValue))
                        return;
                    registerUndo("Change Custom PreIntegrated FDG");
                    usePreIntegratedFDG = evt.newValue;
                    ShaderGraphGUIAnalytics.SendShaderFeatures("toggleUniversalFDG", (int)featureTypeMask, allowFeatureOverride, diffuseModel.ToString());
                    onChange();
                });

                context.AddProperty("Diffuse Quality", new EnumField(DiffuseModel.Low) { value = diffuseModel }, (evt) =>
                {
                    if (Equals(diffuseModel, evt.newValue))
                        return;

                    registerUndo("Change Diffuse Model");
                    diffuseModel = (DiffuseModel)evt.newValue;
                    ShaderGraphGUIAnalytics.SendShaderFeatures("toggleDiffuseModel", (int)featureTypeMask, allowFeatureOverride, diffuseModel.ToString());
                    onChange();
                });

                context.AddProperty("Specular Quality", new EnumField(SpecularModel.Medium) { value = specularModel }, (evt) =>
                {
                    if (Equals(specularModel, evt.newValue))
                        return;

                    registerUndo("Change Specular Model");
                    specularModel = (SpecularModel)evt.newValue;
                    if (HasFeatureType(ScalableLitFeatureTypeMask.Anisotropy))
                        specularModel = SpecularModel.High;
                    onChange();
                });
                context.globalIndentLevel--;
            }
            #endregion

            #region ShadingFeatures
            AddFoldoutController("Shading Features", "Shading Features Foldout", context.globalIndentLevel, ref shadingFeaturesController, ref shadingFeatureFoldout);
            shadingFeaturesController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                shadingFeatureFoldout = !shadingFeatureFoldout;
                onChange();
            });
            context.Add(shadingFeaturesController);

            if (shadingFeatureFoldout)
            {
                context.globalIndentLevel++;
                context.AddProperty("Allow Feature Override", new Toggle() { value = allowFeatureOverride }, (evt) =>
                {
                    if (Equals(allowFeatureOverride, evt.newValue))
                        return;

                    registerUndo("Change Allow Feature Override");
                    allowFeatureOverride = evt.newValue;
                    onChange();
                });

                context.AddProperty("Shading Features", new EnumFlagsField(featureTypeMask) { value = featureTypeMask }, (evt) =>
                {
                    if (Equals(featureTypeMask, evt.newValue))
                        return;
                    registerUndo("Change Feature Type Mask");
                    featureTypeMask = (ScalableLitFeatureTypeMask)evt.newValue;
                    ShaderGraphGUIAnalytics.SendShaderFeatures("UniversalScalableLitSubTarget", (int)featureTypeMask, allowFeatureOverride, diffuseModel.ToString());
                    onChange();
                });
                context.globalIndentLevel--;
            }
            #endregion

            #region PassesControl
            AddFoldoutController("Removed Passes", "Passes Control Foldout", context.globalIndentLevel, ref passesController, ref passesFoldout);
            passesController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                passesFoldout = !passesFoldout;
                onChange();
            });
            context.Add(passesController);

            if (passesFoldout)
            {
                var removedPassList = new ReorderableListView<string>(
                    removedPasses,
                    "Removed Passes",
                    allowReorder: false,
                    showHeader: false);
                removedPassList.style.marginLeft = context.globalIndentLevel * 15;
                removedPassList.GetAddMenuOptions = () => PotentialPassList;

                removedPassList.OnAddMenuItemCallback +=
                (list, addMenuOptionIndex, addMenuOption) =>
                {
                    registerUndo("Change Removed Passes");
                    passStatus[PassName.GetPassID(addMenuOption)] = false;
                    list.Add(addMenuOption);
                    onChange();
                };

                removedPassList.RemoveItemCallback +=
                (list, itemIndex) =>
                {
                    registerUndo("Change Removed Passes");
                    passStatus[PassName.GetPassID(list[itemIndex])] = true;
                    list.RemoveAt(itemIndex);
                    onChange();
                };
                context.Add(removedPassList);
            }
            #endregion

            #region VariantsControl
            AddFoldoutController("Removed Keywords", "Variants Control Foldout", context.globalIndentLevel, ref variantsController, ref variantsFoldout);
            variantsController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                variantsFoldout = !variantsFoldout;
                onChange();
            });
            context.Add(variantsController);

            if (variantsFoldout)
            {
                var removedList = new ReorderableListView<string>(
                    removedVariants,
                    "Removed Keywords",
                    allowReorder: false,
                    showHeader: false);
                removedList.style.marginLeft = context.globalIndentLevel * 15;
                removedList.GetAddMenuOptions = () => PotentialKeywords;

                removedList.OnAddMenuItemCallback +=
                (list, addMenuOptionIndex, addMenuOption) =>
                {
                    registerUndo("Change Removed Keywords");
                    keywordsStatus[KeywordName.GetKeywordID(addMenuOption)] = false;
                    list.Add(addMenuOption);
                    onChange();
                };

                removedList.RemoveItemCallback +=
                (list, itemIndex) =>
                {
                    registerUndo("Change Removed Keywords");
                    keywordsStatus[KeywordName.GetKeywordID(list[itemIndex])] = true;
                    list.RemoveAt(itemIndex);
                    onChange();
                };
                context.Add(removedList);
            }
            #endregion

            #region CustomPassControl
            AddFoldoutController("Custom Pass", "Custom Pass Foldout", context.globalIndentLevel, ref customPassController, ref customPassFoldout);
            customPassController.RegisterCallback<ChangeEvent<bool>>(evt =>
            {
                customPassFoldout = !customPassFoldout;
                onChange();
            });
            context.Add(customPassController);

            if (customPassController.value)
            {
                context.globalIndentLevel++;

                int intentLevel = context.globalIndentLevel;
                var CustomPassCountController = new IntegerManipulationView(customPassCount, "Custom Pass Count:  ", context.globalIndentLevel, maximumCustomPasses);
                CustomPassCountController.OnIncrementCallback +=
                (m_PassCount) =>
                {
                    registerUndo("Change Custom Pass Count");
                    customPassCount = Math.Min(m_PassCount, maximumCustomPasses);
                    CustomPassDescriptorFoldoutUpdate(customPassCount, onChange, intentLevel, 1);
                    onChange();
                };
                CustomPassCountController.OnDecrementCallback +=
                (m_PassCount) =>
                {
                    registerUndo("Change Custom Pass Count");
                    customPassCount = Math.Min(m_PassCount, maximumCustomPasses);
                    CustomPassDescriptorFoldoutUpdate(customPassCount, onChange, intentLevel, 1);
                    onChange();
                };
                context.Add(CustomPassCountController);

                CustomPassDescriptorFoldoutUpdate(customPassCount, onChange, intentLevel, 1);
                for (int i = 0; i < customPassData.Count(); i++)
                {
                    context.Add(customPassFoldoutControls[i].PassController);
                    int index = customPassFoldoutControls.IndexOf(customPassFoldoutControls[i]);
                    if (customPassFoldoutControls[index].PassFoldout)
                    {
                        var LightModeTagsField = new TextField("") { value = customPassData[index].LightModeTags };
                        LightModeTagsField.RegisterCallback<FocusOutEvent>(s =>
                        {
                            if (Equals(customPassData[index].LightModeTags, LightModeTagsField.value))
                                return;
                            registerUndo("Change Custom Pass LightMode Tag");
                            customPassData[index].LightModeTags = LightModeTagsField.value;
                            onChange();
                        });
                        context.AddProperty("LightMode Tag", LightModeTagsField, evt => { });

                        context.AddProperty("Pass Type", new EnumField(CustomPassType.Unlit) { value = customPassData[index].PassType }, (evt) =>
                        {
                            if (Equals(customPassData[index].PassType, evt.newValue))
                                return;
                            registerUndo("Change Custom Pass Type");
                            customPassData[index].PassType = (CustomPassType)evt.newValue;
                            onChange();
                        });
                        context.AddProperty("Surface Type", new EnumField(SurfaceType.Opaque) { value = customPassData[index].SurfaceType }, (evt) =>
                        {
                            if (Equals(customPassData[index].SurfaceType, evt.newValue))
                                return;

                            registerUndo("Change Custom Pass Surface Type");
                            customPassData[index].SurfaceType = (SurfaceType)evt.newValue;
                            onChange();
                        });
                        context.AddProperty("Render Face", new EnumField(RenderFace.Front) { value = customPassData[index].PassRenderFace }, (evt) =>
                        {
                            if (Equals(customPassData[index].PassRenderFace, evt.newValue))
                                return;

                            registerUndo("Change Custom Pass Render Face");
                            customPassData[index].PassRenderFace = (RenderFace)evt.newValue;
                            onChange();
                        });
                        if (customPassData[index].SurfaceType == SurfaceType.Transparent)
                        {
                            context.AddProperty("Blending Mode", new EnumField(AlphaMode.Alpha) { value = customPassData[index].BlendMode }, (evt) =>
                            {
                                if (Equals(customPassData[index].BlendMode, evt.newValue))
                                    return;

                                registerUndo("Change Custom Pass Blending Mode");
                                customPassData[index].BlendMode = (AlphaMode)evt.newValue;
                                onChange();
                            });
                        }
                        context.AddProperty("Depth Write", new EnumField(ZWriteControl.Auto) { value = customPassData[index].ZWrite }, (evt) =>
                        {
                            if (Equals(customPassData[index].ZWrite, evt.newValue))
                                return;

                            registerUndo("Change Custom Pass Depth Write");
                            customPassData[index].ZWrite = (ZWriteControl)evt.newValue;
                            onChange();
                        });
                        context.AddProperty("Depth Test", new EnumField(UniversalTarget.ZTestModeForUI.LEqual) { value = customPassData[index].ZTest }, (evt) =>
                        {
                            if (Equals(customPassData[index].ZTest, evt.newValue))
                                return;

                            registerUndo("Change Custom Pass Depth Test");
                            customPassData[index].ZTest = (UniversalTarget.ZTestModeForUI)evt.newValue;
                            onChange();
                        });
                        context.AddProperty("Alpha Clipping", new Toggle() { value = customPassData[index].AlphaClip }, (evt) =>
                        {
                            if (Equals(customPassData[index].AlphaClip, evt.newValue))
                                return;
                            registerUndo("Change Custom Pass Alpha Clipping");
                            customPassData[index].AlphaClip = evt.newValue;
                            onChange();
                        });

                        context.AddProperty("Override Stencil State", new Toggle() { value = customPassData[index].overrideStencilState }, (evt) =>
                        {
                            if (Equals(customPassData[index].overrideStencilState, evt.newValue))
                                return;
                            registerUndo("Change Custom Pass Override Stencil State");
                            customPassData[index].overrideStencilState = evt.newValue;
                            onChange();
                        });

                        if (customPassData[index].overrideStencilState)
                        {
                            context.globalIndentLevel++;
                            var ReferenceControl = new IntegerField("") { value = customPassData[index].stencilReference };
                            ReferenceControl.RegisterCallback<FocusOutEvent>(
                            evt =>
                            {
                                if (Equals(customPassData[index].stencilReference, ReferenceControl.value))
                                    return;
                                registerUndo("Change Custom Pass Stencil Reference");
                                customPassData[index].stencilReference = Math.Clamp(ReferenceControl.value, 0, 255);
                                onChange();
                            });
                            context.AddProperty("Reference", ReferenceControl, evt=> { });

                            var ReadMaskControl = new IntegerField("") { value = customPassData[index].stencilReadMask };
                            ReadMaskControl.RegisterCallback<FocusOutEvent>(
                            evt =>
                            {
                                if (Equals(customPassData[index].stencilReadMask, ReadMaskControl.value))
                                    return;
                                registerUndo("Change Custom Pass Stencil Read Mask");
                                customPassData[index].stencilReadMask = Math.Clamp(ReadMaskControl.value, 0, 255);
                                onChange();
                            });
                            context.AddProperty("Read Mask", ReadMaskControl, evt=> { });

                            var WriteMaskControl = new IntegerField("") { value = customPassData[index].stencilWriteMask };
                            WriteMaskControl.RegisterCallback<FocusOutEvent>(
                            evt =>
                            {
                                if (Equals(customPassData[index].stencilWriteMask, WriteMaskControl.value))
                                    return;
                                registerUndo("Change Custom Pass Stencil Write Mask");
                                customPassData[index].stencilWriteMask = Math.Clamp(WriteMaskControl.value, 0, 255);
                                onChange();
                            });
                            context.AddProperty("Write Mask", WriteMaskControl, evt=> { });

                            context.AddProperty("Compare", new EnumField(CompareFunction.Always) { value = customPassData[index].stencilCompareFunction }, (evt) =>
                            {
                                if (Equals(customPassData[index].stencilCompareFunction, evt.newValue))
                                    return;
                                registerUndo("Change Custom Pass Stencil Compare Function");
                                customPassData[index].stencilCompareFunction = (CompareFunction)evt.newValue;
                                onChange();
                            });

                            context.AddProperty("Pass", new EnumField(StencilOp.Keep) { value = customPassData[index].passOperation }, (evt) =>
                            {
                                if (Equals(customPassData[index].passOperation, evt.newValue))
                                    return;
                                registerUndo("Change Custom Pass Stencil Pass Operation");
                                customPassData[index].passOperation = (StencilOp)evt.newValue;
                                onChange();
                            });

                            context.AddProperty("Fail", new EnumField(StencilOp.Keep) { value = customPassData[index].failOperation }, (evt) =>
                            {
                                if (Equals(customPassData[index].failOperation, evt.newValue))
                                    return;
                                registerUndo("Change Custom Pass Stencil Fail Operation");
                                customPassData[index].failOperation = (StencilOp)evt.newValue;
                                onChange();
                            });

                            context.AddProperty("Depth Fail", new EnumField(StencilOp.Keep) { value = customPassData[index].zFailOperation }, (evt) =>
                            {
                                if (Equals(customPassData[index].zFailOperation, evt.newValue))
                                    return;
                                registerUndo("Change Custom PassStencil Z Fail Operation");
                                customPassData[index].zFailOperation = (StencilOp)evt.newValue;
                                onChange();
                            });
                            context.globalIndentLevel--;
                        }
                    }
                }

                context.globalIndentLevel--;
            }

            #endregion

        }
        void CustomPassDescriptorFoldoutUpdate(int customPassCount, Action onChange, int indentLevel, int rightIndentLevel)
        {
            if (customPassData == null)
                customPassData = new List<CustomPassData>();
            if (customPassFoldoutControls == null)
                customPassFoldoutControls = new List<CustomPassFoldoutControl>();

            bool ToAddCustomPassFoldoutControl = false;
            if (customPassFoldoutControls != null)
            {
                if (customPassFoldoutControls.Count() > customPassCount)
                {
                    foreach (var customPassControl in customPassFoldoutControls)
                    {
                        int index = customPassFoldoutControls.IndexOf(customPassControl);
                        if (index >= customPassCount)
                        {
                            customPassFoldoutControls[index].PassController.UnregisterCallback<ChangeEvent<bool>>(evt =>
                            {
                                customPassFoldoutControls[index].PassFoldout = !customPassFoldoutControls[index].PassFoldout;
                                onChange();
                            });
                        }
                    }
                    for (int i = customPassFoldoutControls.Count() - 1; i >= customPassCount; i--)
                    {
                        customPassFoldoutControls.RemoveAt(i);
                    }
                }
                else
                    ToAddCustomPassFoldoutControl = true;
            }
            else
                ToAddCustomPassFoldoutControl = true;

            if (ToAddCustomPassFoldoutControl)
            {
                int originalCount = customPassFoldoutControls.Count();
                for (int i = customPassFoldoutControls.Count(); i < customPassCount; i++)
                {
                    customPassFoldoutControls.Add(new CustomPassFoldoutControl(false, i));
                    customPassFoldoutControls[i].PassController.ApplyIndent(indentLevel, rightIndentLevel);
                }
                foreach (var customPassControl in customPassFoldoutControls)
                {
                    int index = customPassFoldoutControls.IndexOf(customPassControl);
                    if (index >= originalCount)
                    {
                        customPassFoldoutControls[index].PassController.RegisterCallback<ChangeEvent<bool>>(evt =>
                        {
                            customPassFoldoutControls[index].PassFoldout = !customPassFoldoutControls[index].PassFoldout;
                            onChange();
                        });
                    }
                }
            }

            bool ToAddCustomData = false;
            if (customPassData != null)
            {
                if (customPassData.Count() > customPassCount)
                {
                    for (int i = customPassData.Count() - 1; i >= customPassCount; i--)
                    {
                        customPassData.RemoveAt(i);
                    }
                }
                else
                    ToAddCustomData = true;
            }
            else
                ToAddCustomData = true;

            if (ToAddCustomData)
            {
                for (int i = customPassData.Count(); i < customPassCount; i++)
                {
                    customPassData.Add(new CustomPassData(i + 1));
                }
            }
        }

        protected override int ComputeMaterialNeedsUpdateHash()
        {
            int hash = base.ComputeMaterialNeedsUpdateHash();
            hash = hash * 23 + target.allowMaterialOverride.GetHashCode();
            return hash;
        }

        public bool TryUpgradeFromMasterNode(IMasterNode1 masterNode, out Dictionary<BlockFieldDescriptor, int> blockMap)
        {
            blockMap = null;
            if (!(masterNode is PBRMasterNode1 pbrMasterNode))
                return false;

            m_WorkflowMode = (WorkflowMode)pbrMasterNode.m_Model;
            m_NormalDropOffSpace = (NormalDropOffSpace)pbrMasterNode.m_NormalDropOffSpace;

            // Handle mapping of Normal block specifically
            BlockFieldDescriptor normalBlock;
            switch (m_NormalDropOffSpace)
            {
                case NormalDropOffSpace.Object:
                    normalBlock = BlockFields.SurfaceDescription.NormalOS;
                    break;
                case NormalDropOffSpace.World:
                    normalBlock = BlockFields.SurfaceDescription.NormalWS;
                    break;
                default:
                    normalBlock = BlockFields.SurfaceDescription.NormalTS;
                    break;
            }

            // Set blockmap
            blockMap = new Dictionary<BlockFieldDescriptor, int>()
            {
                { BlockFields.VertexDescription.Position, 9 },
                { BlockFields.VertexDescription.Normal, 10 },
                { BlockFields.VertexDescription.Tangent, 11 },
                { BlockFields.SurfaceDescription.BaseColor, 0 },
                { normalBlock, 1 },
                { BlockFields.SurfaceDescription.Emission, 4 },
                { BlockFields.SurfaceDescription.Smoothness, 5 },
                { BlockFields.SurfaceDescription.Occlusion, 6 },
                { BlockFields.SurfaceDescription.Alpha, 7 },
                { BlockFields.SurfaceDescription.AlphaClipThreshold, 8 },
            };

            // PBRMasterNode adds/removes Metallic/Specular based on settings
            if (m_WorkflowMode == WorkflowMode.Specular)
                blockMap.Add(BlockFields.SurfaceDescription.Specular, 3);
            else if (m_WorkflowMode == WorkflowMode.Metallic)
                blockMap.Add(BlockFields.SurfaceDescription.Metallic, 2);

            return true;
        }

        internal override void OnAfterParentTargetDeserialized()
        {
            Assert.IsNotNull(target);

            if (this.sgVersion < latestVersion)
            {
                // Upgrade old incorrect Premultiplied blend into
                // equivalent Alpha + Preserve Specular blend mode.
                if (this.sgVersion < 1)
                {
                    if (target.alphaMode == AlphaMode.Premultiply)
                    {
                        target.alphaMode = AlphaMode.Alpha;
                        blendModePreserveSpecular = true;
                    }
                    else
                        blendModePreserveSpecular = false;
                }
                
                // for older version compatibility
                if (featureStatus != null)
                {
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.ClearCoat))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.ClearCoat)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.ClearCoat;
                        }
                    }
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.ThinFilm))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.ThinFilm)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.ThinFilm;
                        }
                    }           
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.DiffractionGratings))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.DiffractionGratings)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.DiffractionGratings;
                        }
                    }       
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.Anisotropy))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.Anisotropy)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.Anisotropy;
                        }
                    }  
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.CustomIndirectDiffuse))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.CustomIndirectDiffuse)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.CustomIndirectDiffuse;
                        }
                    }
                    if (featureStatus.Count > FeatureName.GetFeatureID(FeatureName.CustomIndirectSpecular))
                    {
                        if (featureStatus[FeatureName.GetFeatureID(FeatureName.CustomIndirectSpecular)])
                        {
                            featureTypeMask |= ScalableLitFeatureTypeMask.CustomIndirectSpecular;
                        }
                    }
                }
                
                ChangeVersion(latestVersion);
            }
        }

        #region Struct
        struct ScalableLitTargetParams
        {
            public DiffuseModel diffuseModel;
            public SpecularModel specularModel;
            public bool GI;
            public bool CustomLighting;
            public bool AllowFeatureOverride;
            public bool UsePreIntegratedFDG;
            public StencilStatus stencilStatus;
            public ScalableLitFeatureTypeMask featureTypeMask;
            public List<bool> passStatus;
            public List<bool> keywordsStatus;
            public List<CustomPassData> customPassData;
        }
        #endregion

        #region SubShader
        static class SubShaders
        {

            public static SubShaderDescriptor LitSubShader(UniversalTarget target, ScalableLitTargetParams targetParams, WorkflowMode workflowMode, string renderType, string renderQueue, string disableBatchingTag, bool complexLit, bool blendModePreserveSpecular)
            {
                SubShaderDescriptor result = new SubShaderDescriptor()
                {
                    pipelineTag = UniversalTarget.kPipelineTag,
                    customTags =  complexLit ? UniversalTarget.kComplexLitMaterialTypeTag : UniversalTarget.kLitMaterialTypeTag,
                    renderType = renderType,
                    renderQueue = renderQueue,
                    disableBatchingTag = disableBatchingTag,
                    generatesPreview = true,
                    passes = new PassCollection()
                };

                if (complexLit && targetParams.passStatus[PassName.GetPassID(PassName.forwardPass)])
                    result.passes.Add(ScalableLitPasses.ForwardOnly(target, targetParams, workflowMode, blendModePreserveSpecular, CorePragmas.Forward));
                else if(targetParams.passStatus[PassName.GetPassID(PassName.forwardPass)])
                    result.passes.Add(ScalableLitPasses.Forward(target, targetParams, workflowMode, blendModePreserveSpecular, CorePragmas.Forward));

                // Fills GBuffer too for potential custom usage of the GBuffer.
                if (targetParams.passStatus[PassName.GetPassID(PassName.gBufferPass)])
                    result.passes.Add(ScalableLitPasses.GBuffer(target, targetParams, workflowMode, blendModePreserveSpecular));

                // cull the shadowcaster pass if we know it will never be used
                if ((target.castShadows || target.allowMaterialOverride) && targetParams.passStatus[PassName.GetPassID(PassName.shadowCasterPass)])
                    result.passes.Add(PassVariant(CorePasses.ShadowCaster(target), CorePragmas.Instanced));

                if (target.alwaysRenderMotionVectors)
                    result.customTags = string.Concat(result.customTags, " ", UniversalTarget.kAlwaysRenderMotionVectorsTag);
                result.passes.Add(PassVariant(CorePasses.MotionVectors(target, targetParams.stencilStatus), CorePragmas.MotionVectors));
                
                if (target.mayWriteDepth && targetParams.passStatus[PassName.GetPassID(PassName.depthOnlyPass)])
                    result.passes.Add(PassVariant(CorePasses.DepthOnly(target, targetParams.stencilStatus), CorePragmas.Instanced));

                if (complexLit && targetParams.passStatus[PassName.GetPassID(PassName.depthNormalPass)])
                    result.passes.Add(PassVariant(ScalableLitPasses.DepthNormalOnly(target, targetParams), CorePragmas.Instanced));
                else if (targetParams.passStatus[PassName.GetPassID(PassName.depthNormalPass)])
                    result.passes.Add(PassVariant(ScalableLitPasses.DepthNormal(target, targetParams), CorePragmas.Instanced));

                if (targetParams.passStatus[PassName.GetPassID(PassName.metaPass)])
                    result.passes.Add(PassVariant(ScalableLitPasses.Meta(target), CorePragmas.Default));

                // Currently neither of these passes (selection/picking) can be last for the game view for
                // UI shaders to render correctly. Verify [1352225] before changing this order.
                if (targetParams.passStatus[PassName.GetPassID(PassName.sceneSelectionPass)])
                    result.passes.Add(PassVariant(CorePasses.SceneSelection(target), CorePragmas.Default));
                if (targetParams.passStatus[PassName.GetPassID(PassName.scenePickingPass)])
                    result.passes.Add(PassVariant(CorePasses.ScenePicking(target), CorePragmas.Default));
                if(targetParams.passStatus[PassName.GetPassID(PassName._2DPass)])
                    result.passes.Add(PassVariant(ScalableLitPasses._2D(target, targetParams), CorePragmas.Default));

                for (int i = 0; i < targetParams.customPassData.Count(); i++)
                {
                    if (targetParams.customPassData[i].PassType == CustomPassType.Lit)
                        result.passes.Add(ScalableLitPasses.Forward(target, targetParams, workflowMode, blendModePreserveSpecular, CorePragmas.Forward, true, i));
                    else
                        result.passes.Add(ScalableLitPasses.UnlitPass(target, targetParams, i));
                }
                return result;
            }
        }
        #endregion

        #region Passes
        static class ScalableLitPasses
        {
            static void AddKeywordsControlToForwardPass(ref PassDescriptor passDesc, ScalableLitTargetParams targetParams)
            {
                for (int i = 0; i < PotentialForwardKeywords.Count(); i++)
                {
                    if (targetParams.keywordsStatus[KeywordName.GetKeywordID(PotentialForwardKeywords[i])])
                        passDesc.keywords.Add(KeywordName.GetDesc(PotentialForwardKeywords[i]));
                }
            }
            static void AddKeywordsControlToGBufferPass(ref PassDescriptor passDesc, ScalableLitTargetParams targetParams)
            {
                for (int i = 0; i < PotentialGBufferKeywords.Count(); i++)
                {
                    if (targetParams.keywordsStatus[KeywordName.GetKeywordID(PotentialGBufferKeywords[i])])
                        passDesc.keywords.Add(KeywordName.GetDesc(PotentialGBufferKeywords[i]));
                }
            }

            static void AddWorkflowModeControlToPass(ref PassDescriptor pass, UniversalTarget target, WorkflowMode workflowMode)
            {
                if (target.allowMaterialOverride)
                    pass.keywords.Add(ScalableLitDefines.SpecularSetup);
                else if (workflowMode == WorkflowMode.Specular)
                    pass.defines.Add(ScalableLitDefines.SpecularSetup, 1);
            }

            static void AddReceiveShadowsControlToPass(ref PassDescriptor pass, UniversalTarget target, bool receiveShadows)
            {
                if (target.allowMaterialOverride)
                    pass.keywords.Add(ScalableLitKeywords.ReceiveShadowsOff);
                else if (!receiveShadows)
                    pass.defines.Add(ScalableLitKeywords.ReceiveShadowsOff, 1);
            }

            public static PassDescriptor Forward(
                UniversalTarget target,
                ScalableLitTargetParams targetParams,
                WorkflowMode workflowMode,
                bool blendModePreserveSpecular,
                PragmaCollection pragmas,
                bool isCustomPass = false,
                int customPassIndex = 0
                )
            {
                var block = ScalableLitBlockMasks.FragmentLit;
                KeywordCollection keywordCollection = new KeywordCollection { ScalableLitKeywords.Forward };

                // defines
                DefineCollection defineCollections = new DefineCollection { CoreDefines.UseFragmentFog };
                defineCollections.Add(CoreKeywordDescriptors.DiffuseModel_Lambert, 1);
                defineCollections.Add(CoreKeywordDescriptors.SpecularModel_ApproxCookTorrance, 1);

                // custom indirect specular
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.CustomIndirectSpecular) && !isCustomPass)
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomIndirectSpecular).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.IndirectSpecularMask).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.CustomIndirectSpecular);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.CustomIndirectSpecular, 1);
                }

                // custom indirect diffuse
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.CustomIndirectDiffuse) && !isCustomPass)
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomIndirectDiffuse).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.IndirectDiffuseMask).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.CustomIndirectDiffuse);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.CustomIndirectDiffuse, 1);
                }

                var result = new PassDescriptor()
                {
                    // Definition
                    displayName = "Universal Forward",
                    referenceName = "SHADERPASS_FORWARD",
                    lightMode = isCustomPass ? targetParams.customPassData[customPassIndex].LightModeTags : "UniversalForward",
                    useInPreview = !isCustomPass,
                    isCustomPass = isCustomPass,
                    customPassNum = customPassIndex,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = isCustomPass ? new BlockFieldDescriptor[] { } : CoreBlockMasks.Vertex,
                    validPixelBlocks = isCustomPass ? new BlockFieldDescriptor[] { } : block,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = ScalableLitRequiredFields.Forward,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = isCustomPass ? new RenderStateCollection { } : CoreRenderStates.UberSwitchedRenderState(target, blendModePreserveSpecular),
                    pragmas = pragmas,     // NOTE: SM 2.0 only GL
                    defines = defineCollections,
                    keywords = keywordCollection,
                    includes = ScalableLitIncludes.Forward,

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };

                if (isCustomPass)
                {
                    StencilStatus CustomPassStencil = new StencilStatus
                    {
                        overrideStencilState = targetParams.customPassData[customPassIndex].overrideStencilState,
                        stencilReference = targetParams.customPassData[customPassIndex].stencilReference,
                        stencilReadMask = targetParams.customPassData[customPassIndex].stencilReadMask,
                        stencilWriteMask = targetParams.customPassData[customPassIndex].stencilWriteMask,
                        stencilCompareFunction = targetParams.customPassData[customPassIndex].stencilCompareFunction,
                        passOperation = targetParams.customPassData[customPassIndex].passOperation,
                        failOperation = targetParams.customPassData[customPassIndex].failOperation,
                        zFailOperation = targetParams.customPassData[customPassIndex].zFailOperation
                    };
                    AddStencilStatusControl(ref result, CustomPassStencil);
                }
                else
                    AddStencilStatusControl(ref result, targetParams.stencilStatus);
                if (isCustomPass)
                    AddCustomPassControls(ref result, targetParams.customPassData[customPassIndex], blendModePreserveSpecular);
                else
                {
                    CorePasses.AddAlphaToMaskControlToPass(ref result, target);
                    CorePasses.AddTargetSurfaceControlsToPass(ref result, target, blendModePreserveSpecular);
                } 
                
                AddKeywordsControlToForwardPass(ref result, targetParams);
                AddWorkflowModeControlToPass(ref result, target, workflowMode);
                AddReceiveShadowsControlToPass(ref result, target, target.receiveShadows);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }

            public static PassDescriptor ForwardOnly(
                UniversalTarget target,
                ScalableLitTargetParams targetParams,
                WorkflowMode workflowMode,
                bool blendModePreserveSpecular,
                PragmaCollection pragmas
                )
            {

                var block = ScalableLitBlockMasks.FragmentLit;
                DefineCollection defineCollections = new DefineCollection { CoreDefines.UseFragmentFog };
                KeywordCollection keywordCollection = new KeywordCollection { ScalableLitKeywords.Forward };
                defineCollections.Add(CoreKeywordDescriptors.ScalableLit, 1);

                // thin film
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.ThinFilm))
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.ThinFilmThickness).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.ThinFilmMask).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.ThinFilm);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.ThinFilm, 1);
                }

                // diffraction gratings
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.DiffractionGratings))
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.SlitsDistance).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.SlitsMask).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.SlitsDirection).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.DiffractionGratings);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.DiffractionGratings, 1);
                }

                // custom indirect specular
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.CustomIndirectSpecular))
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomIndirectSpecular).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.IndirectSpecularMask).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.CustomIndirectSpecular);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.CustomIndirectSpecular, 1);
                }

                // custom indirect diffuse
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.CustomIndirectDiffuse))
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomIndirectDiffuse).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.IndirectDiffuseMask).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.CustomIndirectDiffuse);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.CustomIndirectDiffuse, 1);
                }

                // clear coat
                if (UniversalTarget.HasFeatureType(targetParams.featureTypeMask, ScalableLitFeatureTypeMask.ClearCoat))
                {
                    block = block.Append(BlockFields.SurfaceDescription.CoatMask).ToArray();
                    block = block.Append(BlockFields.SurfaceDescription.CoatSmoothness).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.ClearCoatNormal).ToArray();
                    if (targetParams.AllowFeatureOverride)
                        keywordCollection.Add(CoreKeywordDescriptors.ClearCoat);
                    else
                        defineCollections.Add(CoreKeywordDescriptors.ClearCoat, 1);
                }

                // diffuse model
                if (targetParams.diffuseModel == DiffuseModel.High)
                    defineCollections.Add(CoreKeywordDescriptors.DiffuseModel_Disney, 1);
                else if (targetParams.diffuseModel == DiffuseModel.Low)
                    defineCollections.Add(CoreKeywordDescriptors.DiffuseModel_Lambert, 1);

                // specular model
                if (targetParams.specularModel == SpecularModel.Low)
                    defineCollections.Add(CoreKeywordDescriptors.SpecularModel_BlinnPhong, 1);
                else if (targetParams.specularModel == SpecularModel.High)
                {
                    defineCollections.Add(CoreKeywordDescriptors.SpecularModel_Aniso, 1);
                    block = block.Append(UniversalBlockFields.SurfaceDescription.Anisotropy).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.Tangent).ToArray();
                }
                else if (targetParams.specularModel == SpecularModel.Medium)
                    defineCollections.Add(CoreKeywordDescriptors.SpecularModel_ApproxCookTorrance, 1);

                // GI
                if (!targetParams.GI)
                    defineCollections.Add(ScalableLitKeywords.GI_Off, 1);

                // CUSTOM LIGHTING
                if (targetParams.CustomLighting)
                {
                    defineCollections.Add(ScalableLitKeywords.CustomLighting, 1);
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomLighting).ToArray();
                }

                // PreIntegratedFDG
                if (targetParams.UsePreIntegratedFDG)
                {
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomSpecularFDG).ToArray();
                    block = block.Append(UniversalBlockFields.SurfaceDescription.CustomEnergyCompensation).ToArray();
                    defineCollections.Add(CoreKeywordDescriptors.UsePreIntegratedFDG, 1);
                }

                // keywords
                var result = new PassDescriptor
                {
                    // Definition
                    displayName = "Universal Forward Only",
                    referenceName = "SHADERPASS_FORWARDONLY",
                    lightMode = "UniversalForwardOnly",
                    useInPreview = true,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = block,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = ScalableLitRequiredFields.Forward,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.UberSwitchedRenderState(target, blendModePreserveSpecular),
                    pragmas = pragmas,
                    defines = defineCollections,
                    keywords = keywordCollection,
                    includes = new IncludeCollection { ScalableLitIncludes.Forward },

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                AddStencilStatusControl(ref result, targetParams.stencilStatus);
                CorePasses.AddTargetSurfaceControlsToPass(ref result, target, blendModePreserveSpecular);
                CorePasses.AddAlphaToMaskControlToPass(ref result, target);
                AddKeywordsControlToForwardPass(ref result, targetParams);
                AddWorkflowModeControlToPass(ref result, target, workflowMode);
                AddReceiveShadowsControlToPass(ref result, target, target.receiveShadows);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }

            // Deferred only in SM4.5, MRT not supported in GLES2
            public static PassDescriptor GBuffer(UniversalTarget target,
            ScalableLitTargetParams targetParams,
            WorkflowMode workflowMode, bool blendModePreserveSpecular)
            {

                var result = new PassDescriptor
                {
                    // Definition
                    displayName = "GBuffer",
                    referenceName = "SHADERPASS_GBUFFER",
                    lightMode = "UniversalGBuffer",
                    useInPreview = true,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = ScalableLitBlockMasks.FragmentLit,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = ScalableLitRequiredFields.GBuffer,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.UberSwitchedRenderState(target, blendModePreserveSpecular),
                    pragmas = CorePragmas.GBuffer,
                    defines = new DefineCollection { CoreDefines.UseFragmentFog },
                    keywords = new KeywordCollection() { ScalableLitKeywords.GBuffer },
                    includes = new IncludeCollection { ScalableLitIncludes.GBuffer },

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                AddStencilStatusControl(ref result, targetParams.stencilStatus);
                AddKeywordsControlToGBufferPass(ref result, targetParams);
                CorePasses.AddTargetSurfaceControlsToPass(ref result, target, blendModePreserveSpecular);
                AddWorkflowModeControlToPass(ref result, target, workflowMode);
                AddReceiveShadowsControlToPass(ref result, target, target.receiveShadows);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }

            public static PassDescriptor Meta(UniversalTarget target)
            {
                var result = new PassDescriptor()
                {
                    // Definition
                    displayName = "Meta",
                    referenceName = "SHADERPASS_META",
                    lightMode = "Meta",

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = ScalableLitBlockMasks.FragmentMeta,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = ScalableLitRequiredFields.Meta,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.Meta,
                    pragmas = CorePragmas.Default,
                    defines = new DefineCollection() { CoreDefines.UseFragmentFog },
                    keywords = new KeywordCollection() { CoreKeywordDescriptors.EditorVisualization },
                    includes = ScalableLitIncludes.Meta,

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                CorePasses.AddAlphaClipControlToPass(ref result, target);

                return result;
            }

            public static PassDescriptor _2D(UniversalTarget target, ScalableLitTargetParams targetParams)
            {
                var result = new PassDescriptor()
                {
                    // Definition
                    referenceName = "SHADERPASS_2D",
                    lightMode = "Universal2D",

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = CoreBlockMasks.FragmentColorAlpha,

                    // Fields
                    structs = CoreStructCollections.Default,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.UberSwitchedRenderState(target),
                    pragmas = CorePragmas.Instanced,
                    defines = new DefineCollection(),
                    keywords = new KeywordCollection(),
                    includes = ScalableLitIncludes._2D,

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                AddStencilStatusControl(ref result, targetParams.stencilStatus);
                CorePasses.AddAlphaClipControlToPass(ref result, target);

                return result;
            }

            public static PassDescriptor DepthNormal(UniversalTarget target, ScalableLitTargetParams targetParams)
            {
                var result = new PassDescriptor()
                {
                    // Definition
                    displayName = "DepthNormals",
                    referenceName = "SHADERPASS_DEPTHNORMALS",
                    lightMode = "DepthNormals",
                    useInPreview = true,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = CoreBlockMasks.FragmentDepthNormals,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = CoreRequiredFields.DepthNormals,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.DepthNormalsOnly(target),
                    pragmas = CorePragmas.Instanced,
                    defines = new DefineCollection(),
                    keywords = new KeywordCollection(),
                    includes = new IncludeCollection { CoreIncludes.DepthNormalsOnly },

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                AddStencilStatusControl(ref result, targetParams.stencilStatus);
                CorePasses.AddAlphaClipControlToPass(ref result, target);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }

            public static PassDescriptor DepthNormalOnly(UniversalTarget target, ScalableLitTargetParams targetParams)
            {
                var result = new PassDescriptor()
                {
                    // Definition
                    displayName = "DepthNormalsOnly",
                    referenceName = "SHADERPASS_DEPTHNORMALSONLY",
                    lightMode = "DepthNormalsOnly",
                    useInPreview = true,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = CoreBlockMasks.Vertex,
                    validPixelBlocks = CoreBlockMasks.FragmentDepthNormals,

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = CoreRequiredFields.DepthNormals,
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = CoreRenderStates.DepthNormalsOnly(target),
                    pragmas = CorePragmas.Instanced,
                    defines = new DefineCollection(),
                    keywords = new KeywordCollection(),
                    includes = new IncludeCollection { CoreIncludes.DepthNormalsOnly },

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };
                AddStencilStatusControl(ref result, targetParams.stencilStatus);
                CorePasses.AddAlphaClipControlToPass(ref result, target);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }
                   
            public static PassDescriptor UnlitPass(UniversalTarget target, ScalableLitTargetParams targetParams, int customPassIndex = 0)
            {
                KeywordCollection keywords = new KeywordCollection { }; //UnlitKeywords.Forward;
                var result = new PassDescriptor
                {                
                    // Definition
                    displayName = "Universal Forward",
                    referenceName = "SHADERPASS_UNLIT",
                    lightMode = targetParams.customPassData[customPassIndex].LightModeTags,
                    useInPreview = false,
                    isCustomPass = true,
                    customPassNum = customPassIndex,

                    // Template
                    passTemplatePath = UniversalTarget.kUberTemplatePath,
                    sharedTemplateDirectories = UniversalTarget.kSharedTemplateDirectories,

                    // Port Mask
                    validVertexBlocks = new BlockFieldDescriptor[] { },
                    validPixelBlocks = new BlockFieldDescriptor[] { },

                    // Fields
                    structs = CoreStructCollections.Default,
                    requiredFields = new FieldCollection()
                    {
                        StructFields.Varyings.positionWS,
                        StructFields.Varyings.normalWS
                    },
                    fieldDependencies = CoreFieldDependencies.Default,

                    // Conditional State
                    renderStates = new RenderStateCollection{ },
                    pragmas = CorePragmas.Forward,
                    defines = new DefineCollection { CoreDefines.UseFragmentFog },
                    keywords = new KeywordCollection{ keywords },
                    includes = new IncludeCollection { ScalableLitIncludes.Unlit },

                    // Custom Interpolator Support
                    customInterpolators = CoreCustomInterpDescriptors.Common
                };

                StencilStatus CustomPassStencil = new StencilStatus
                {
                    overrideStencilState = targetParams.customPassData[customPassIndex].overrideStencilState,
                    stencilReference = targetParams.customPassData[customPassIndex].stencilReference,
                    stencilReadMask = targetParams.customPassData[customPassIndex].stencilReadMask,
                    stencilWriteMask = targetParams.customPassData[customPassIndex].stencilWriteMask,
                    stencilCompareFunction = targetParams.customPassData[customPassIndex].stencilCompareFunction,
                    passOperation = targetParams.customPassData[customPassIndex].passOperation,
                    failOperation = targetParams.customPassData[customPassIndex].failOperation,
                    zFailOperation = targetParams.customPassData[customPassIndex].zFailOperation
                };
                AddStencilStatusControl(ref result, CustomPassStencil);
                AddCustomPassControls(ref result, targetParams.customPassData[customPassIndex]);
                CorePasses.AddLODCrossFadeControlToPass(ref result, target);

                return result;
            }
        }


        #endregion

        #region PortMasks
        static class ScalableLitBlockMasks
        {
            public static readonly BlockFieldDescriptor[] FragmentLit = new BlockFieldDescriptor[]
            {
                BlockFields.SurfaceDescription.BaseColor,
                BlockFields.SurfaceDescription.NormalOS,
                BlockFields.SurfaceDescription.NormalTS,
                BlockFields.SurfaceDescription.NormalWS,
                BlockFields.SurfaceDescription.Emission,
                BlockFields.SurfaceDescription.Metallic,
                BlockFields.SurfaceDescription.Specular,
                BlockFields.SurfaceDescription.Smoothness,
                BlockFields.SurfaceDescription.Occlusion,
                BlockFields.SurfaceDescription.Alpha,
                BlockFields.SurfaceDescription.AlphaClipThreshold,
            };
            public static readonly BlockFieldDescriptor[] FragmentMeta = new BlockFieldDescriptor[]
            {
                BlockFields.SurfaceDescription.BaseColor,
                BlockFields.SurfaceDescription.Emission,
                BlockFields.SurfaceDescription.Alpha,
                BlockFields.SurfaceDescription.AlphaClipThreshold,
            };
        }
        #endregion

        #region RequiredFields
        static class ScalableLitRequiredFields
        {
            public static readonly FieldCollection Forward = new FieldCollection()
            {
                StructFields.Attributes.uv1,
                StructFields.Attributes.uv2,
                StructFields.Varyings.positionWS,
                StructFields.Varyings.normalWS,
                StructFields.Varyings.tangentWS,                        // needed for vertex lighting
                UniversalStructFields.Varyings.staticLightmapUV,
                UniversalStructFields.Varyings.dynamicLightmapUV,
                UniversalStructFields.Varyings.sh,
                UniversalStructFields.Varyings.fogFactorAndVertexLight, // fog and vertex lighting, vert input is dependency
                UniversalStructFields.Varyings.shadowCoord,             // shadow coord, vert input is dependency
            };

            public static readonly FieldCollection GBuffer = new FieldCollection()
            {
                StructFields.Attributes.uv1,
                StructFields.Attributes.uv2,
                StructFields.Varyings.positionWS,
                StructFields.Varyings.normalWS,
                StructFields.Varyings.tangentWS,                        // needed for vertex lighting
                UniversalStructFields.Varyings.staticLightmapUV,
                UniversalStructFields.Varyings.dynamicLightmapUV,
                UniversalStructFields.Varyings.sh,
                UniversalStructFields.Varyings.fogFactorAndVertexLight, // fog and vertex lighting, vert input is dependency
                UniversalStructFields.Varyings.shadowCoord,             // shadow coord, vert input is dependency
            };

            public static readonly FieldCollection Meta = new FieldCollection()
            {
                StructFields.Attributes.positionOS,
                StructFields.Attributes.normalOS,
                StructFields.Attributes.uv0,                            //
                StructFields.Attributes.uv1,                            // needed for meta vertex position
                StructFields.Attributes.uv2,                            // needed for meta UVs
                StructFields.Attributes.instanceID,                     // needed for rendering instanced terrain
                StructFields.Varyings.positionCS,
                StructFields.Varyings.texCoord0,                        // needed for meta UVs
                StructFields.Varyings.texCoord1,                        // VizUV
                StructFields.Varyings.texCoord2,                        // LightCoord
            };
        }
        #endregion

        #region Defines
        static class ScalableLitDefines
        {
            public static readonly KeywordDescriptor SpecularSetup = new KeywordDescriptor()
            {
                displayName = "Specular Setup",
                referenceName = "_SPECULAR_SETUP",
                type = KeywordType.Boolean,
                definition = KeywordDefinition.ShaderFeature,
                scope = KeywordScope.Local,
                stages = KeywordShaderStage.Fragment
            };
        }
        #endregion

        #region Keywords
        static class ScalableLitKeywords
        {
            public static readonly KeywordDescriptor ReceiveShadowsOff = new KeywordDescriptor()
            {
                displayName = "Receive Shadows Off",
                referenceName = ShaderKeywordStrings._RECEIVE_SHADOWS_OFF,
                type = KeywordType.Boolean,
                definition = KeywordDefinition.ShaderFeature,
                scope = KeywordScope.Local,
            };
            public static readonly KeywordDescriptor GI_Off = new KeywordDescriptor()
            {
                displayName = "Receive GI Off",
                referenceName = "_GLOBAL_ILLUMINATION_OFF",
                type = KeywordType.Boolean,
                definition = KeywordDefinition.Predefined,
                scope = KeywordScope.Local,
                stages = KeywordShaderStage.Fragment
            };

            public static readonly KeywordDescriptor CustomLighting = new KeywordDescriptor()
            {
                displayName = "Use Custom Lighting",
                referenceName = "_USE_CUSTOM_LIGHTING_ON",
                type = KeywordType.Boolean,
                definition = KeywordDefinition.Predefined,
                scope = KeywordScope.Local,
                stages = KeywordShaderStage.Fragment
            };

            public static readonly KeywordCollection Forward = new KeywordCollection
            {
                { CoreKeywordDescriptors.DebugDisplay },
                { CoreKeywordDescriptors.ClusteredLighting },
            };

            public static readonly KeywordCollection GBuffer = new KeywordCollection
            {
                { CoreKeywordDescriptors.GBufferNormalsOct },
                { CoreKeywordDescriptors.RenderPassEnabled },
                { CoreKeywordDescriptors.DebugDisplay },
            };
        }
        #endregion

        #region PotentialFeatureList
        [Obsolete("Use feature mask instead", false)]
        public static readonly List<string> PotentialFeatureList = new List<string>()
        {
            { FeatureName.ClearCoat },
            { FeatureName.ThinFilm },
            { FeatureName.DiffractionGratings },
            { FeatureName.Anisotropy},
            { FeatureName.CustomIndirectDiffuse},
            { FeatureName.CustomIndirectSpecular}
        };
        #endregion
        #region PotentialPassList
        public static readonly List<string> PotentialPassList = new List<string>()
        {
            { PassName.forwardPass },
            { PassName.shadowCasterPass },
            { PassName.depthOnlyPass },
            { PassName.depthNormalPass },
            { PassName.gBufferPass },
            { PassName.metaPass },
            { PassName.sceneSelectionPass },
            { PassName.scenePickingPass },
            { PassName._2DPass },
        };
        #endregion
        #region PotentialKeywordsList
        public static readonly List<string> PotentialForwardKeywords = new List<string>()
        {
            KeywordName.screenSpaceAmbientOcclusion,
            KeywordName.staticLightmap,
            KeywordName.dynamicLightmap,
            KeywordName.directionalLightmapCombined,
            KeywordName.mainLightShadows,
            KeywordName.additionalLights,
            KeywordName.additionalLightShadows,
            KeywordName.reflectionProbeBlending,
            KeywordName.reflectionProbeBoxProjection,
            KeywordName.shadowsSoft,
            KeywordName.lightmapShadowMixing,
            KeywordName.shadowsShadowmask,
            KeywordName.dBuffer,
            KeywordName.lightLayers,
            KeywordName.lightCookies,
            KeywordName.evaluateSH
        };

        public static readonly List<string> PotentialGBufferKeywords = new List<string>()
        {
            KeywordName.staticLightmap,
            KeywordName.dynamicLightmap,
            KeywordName.directionalLightmapCombined,
            KeywordName.mainLightShadows,
            KeywordName.reflectionProbeBlending,
            KeywordName.reflectionProbeBoxProjection,
            KeywordName.shadowsSoft,
            KeywordName.lightmapShadowMixing,
            KeywordName.shadowsShadowmask,
            KeywordName.mixedLightingSubtractive,
            KeywordName.dBuffer,
        };
        public static readonly List<string> PotentialKeywords = PotentialForwardKeywords.Union(PotentialGBufferKeywords).ToList();

        #endregion

        #region Includes
        static class ScalableLitIncludes
        {
            const string kShadows = "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl";
            const string kMetaInput = "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl";
            const string kForwardPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/PBRScalableForwardPass.hlsl";
            const string kGBuffer = "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl";
            const string kPBRGBufferPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/PBRGBufferPass.hlsl";
            const string kLightingMetaPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/LightingMetaPass.hlsl";
            const string k2DPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/PBR2DPass.hlsl";
            const string kUnlitPass = "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/UnlitPass.hlsl";

            public static readonly IncludeCollection Unlit = new IncludeCollection
            {
                // Pre-graph
                { CoreIncludes.DOTSPregraph },
                { CoreIncludes.WriteRenderLayersPregraph },
                { CoreIncludes.CorePregraph },
                { CoreIncludes.ShaderGraphPregraph },
                { CoreIncludes.DBufferPregraph },

                // Post-graph
                { CoreIncludes.CorePostgraph },
                { kUnlitPass, IncludeLocation.Postgraph },
            };
            public static readonly IncludeCollection Forward = new IncludeCollection
            {
                // Pre-graph
                { CoreIncludes.DOTSPregraph },
                { CoreIncludes.WriteRenderLayersPregraph },
                { CoreIncludes.CorePregraph },
                { kShadows, IncludeLocation.Pregraph },
                { CoreIncludes.ShaderGraphPregraph },
                { CoreIncludes.DBufferPregraph },

                // Post-graph
                { CoreIncludes.CorePostgraph },
                { kForwardPass, IncludeLocation.Postgraph },
            };

            public static readonly IncludeCollection GBuffer = new IncludeCollection
            {
                // Pre-graph
                { CoreIncludes.DOTSPregraph },
                { CoreIncludes.WriteRenderLayersPregraph },
                { CoreIncludes.CorePregraph },
                { kShadows, IncludeLocation.Pregraph },
                { CoreIncludes.ShaderGraphPregraph },
                { CoreIncludes.DBufferPregraph },

                // Post-graph
                { CoreIncludes.CorePostgraph },
                { kGBuffer, IncludeLocation.Postgraph },
                { kPBRGBufferPass, IncludeLocation.Postgraph },
            };

            public static readonly IncludeCollection Meta = new IncludeCollection
            {
                // Pre-graph
                { CoreIncludes.CorePregraph },
                { CoreIncludes.ShaderGraphPregraph },
                { kMetaInput, IncludeLocation.Pregraph },

                // Post-graph
                { CoreIncludes.CorePostgraph },
                { kLightingMetaPass, IncludeLocation.Postgraph },
            };

            public static readonly IncludeCollection _2D = new IncludeCollection
            {
                // Pre-graph
                { CoreIncludes.CorePregraph },
                { CoreIncludes.ShaderGraphPregraph },

                // Post-graph
                { CoreIncludes.CorePostgraph },
                { k2DPass, IncludeLocation.Postgraph },
            };
        }
        #endregion
    }
}
