using System;
using System.Collections.Generic;
using UnityEngine;
using NameAndTooltip = UnityEngine.Rendering.DebugUI.Widget.NameAndTooltip;

namespace UnityEngine.Rendering.Universal
{
    public class DebugDisplaySettingsGDRP : IDebugDisplaySettingsData
    {
        public DebugBufferVisualization bufferVisualizationMode { get; set; }

        // public DebugVirtualShadowMapVisualization virtualShadowMapVisualizationMode { get; set; }

        static internal class Strings
        {
            public static readonly NameAndTooltip BufferVisualization = new() {name = "Buffer Visualization", tooltip = "Buffer Visualization Mode" };
            // public static readonly NameAndTooltip VirtualShadowMapVisualization = new() { name = "VirtualShadowMap Visualization", tooltip = "VirtualShadowMap Visualization Mode" };
        }

        internal static class WidgetFactory
        {
            internal static DebugUI.Widget CreateBufferVisualizationMode(SettingsPanel panel) => new DebugUI.EnumField
            {
                nameAndTooltip = Strings.BufferVisualization,
                autoEnum = typeof(DebugBufferVisualization),
                getter = () => (int)panel.data.bufferVisualizationMode,
                setter = (value) => panel.data.bufferVisualizationMode = (DebugBufferVisualization)value,
                getIndex = () => (int)panel.data.bufferVisualizationMode,
                setIndex = (value) => panel.data.bufferVisualizationMode = (DebugBufferVisualization)value,
            };

            //internal static DebugUI.Widget CreateVirtualShadowMapVisualizationMode(SettingsPanel panel) => new DebugUI.EnumField
            //{
            //    nameAndTooltip = Strings.VirtualShadowMapVisualization,
            //    autoEnum = typeof(DebugVirtualShadowMapVisualization),
            //    getter = () => (int)panel.data.virtualShadowMapVisualizationMode,
            //    setter = (value) => panel.data.virtualShadowMapVisualizationMode = (DebugVirtualShadowMapVisualization)value,
            //    getIndex = () => (int)panel.data.virtualShadowMapVisualizationMode,
            //    setIndex = (value) => panel.data.virtualShadowMapVisualizationMode = (DebugVirtualShadowMapVisualization)value,
            //};
        }

        [DisplayInfo(name = "GDRP", order = 5)]
        internal class SettingsPanel : DebugDisplaySettingsPanel<DebugDisplaySettingsGDRP>
        {
            public SettingsPanel(DebugDisplaySettingsGDRP data)
                : base(data)
            {
                AddWidget(DebugDisplaySettingsCommon.WidgetFactory.CreateMissingDebugShadersWarning());

                AddWidget(new DebugUI.Foldout
                {
                    displayName = "GDRP Debug Modes",
                    flags = DebugUI.Flags.FrequentlyUsed,
                    isHeader = true,
                    opened = true,
                    children =
                    {
                        WidgetFactory.CreateBufferVisualizationMode(this),
                        //WidgetFactory.CreateVirtualShadowMapVisualizationMode(this),
                    }
                });
            }
        }

        #region IDebugDisplaySettingsData

        /// <inheritdoc/>
        public bool AreAnySettingsActive => (bufferVisualizationMode != DebugBufferVisualization.None) /*|| (virtualShadowMapVisualizationMode != DebugVirtualShadowMapVisualization.None)*/;

        /// <inheritdoc/>
        public bool IsPostProcessingAllowed => true;

        /// <inheritdoc/>
        public bool IsLightingActive => true;

        /// <inheritdoc/>
        public bool TryGetScreenClearColor(ref Color color)
        {
            return false;
        }

        IDebugDisplaySettingsPanelDisposable IDebugDisplaySettingsData.CreatePanel()
        {
            return new SettingsPanel(this);
        }

        #endregion
    }
}
