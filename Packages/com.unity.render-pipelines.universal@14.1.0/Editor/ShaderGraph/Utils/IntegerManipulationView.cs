using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEditor;
using UnityEditorInternal;
using UnityEngine;
using UnityEngine.UIElements;

namespace UnityEditor.Rendering.Universal.ShaderGraph
{
    internal class IntegerManipulationView : VisualElement
    {
        public int m_Count;
        string m_HeaderLabel;
        bool m_ShowHeader;
        const int kIndentWidthInPixel = 15;
        public int globalIndentLevel { get; set; } = 0;
        public int m_MaximumCount = 15;

        VisualElement m_ButtonContainer;
        Button IncrementButton;
        Button DecrementButton;
        Label CountDisplay;
        Color backgroundColor = new Color(0.345f, 0.345f, 0.345f);
        BackgroundSize buttonSize = new BackgroundSize(18, 18);
        internal IntegerManipulationView(
            int count,
            string header = "Count:",
            int intentLevel = 0,
            int maximumCount = 15,
            bool showHeader = true)
        {
            m_Count = count;
            m_HeaderLabel = header;
            m_ShowHeader = showHeader;
            m_MaximumCount = maximumCount;
            if (m_ShowHeader)
            {
                CountDisplay = new Label(header + m_Count);
                CountDisplay.style.marginLeft = kIndentWidthInPixel * (globalIndentLevel + intentLevel);
                CountDisplay.style.marginRight = 10;
                CountDisplay.style.marginTop = 5;
                CountDisplay.style.borderTopWidth = 5;
                CountDisplay.style.borderBottomWidth = 5;
                CountDisplay.style.borderLeftWidth = 6;
                CountDisplay.style.borderRightWidth = 6;
                CountDisplay.style.borderTopLeftRadius = 0;
                CountDisplay.style.backgroundColor = backgroundColor;
                Add(CountDisplay);
            }

            m_ButtonContainer = new VisualElement();
            m_ButtonContainer.style.alignItems = Align.FlexStart;
            m_ButtonContainer.style.flexDirection = FlexDirection.Row;
            m_ButtonContainer.style.justifyContent = Justify.FlexEnd;
            m_ButtonContainer.style.marginRight = 15;
            m_ButtonContainer.style.marginLeft = kIndentWidthInPixel * (globalIndentLevel + intentLevel);

            IncrementButton = new Button() { text = "+" };
            IncrementButton.style.marginTop = 0;
            IncrementButton.style.marginRight = 0;
            IncrementButton.style.marginLeft = 0;
            IncrementButton.style.marginBottom = 5;
            IncrementButton.style.borderTopColor = backgroundColor;
            IncrementButton.style.borderBottomColor = backgroundColor;
            IncrementButton.style.borderLeftColor = backgroundColor;
            IncrementButton.style.borderRightColor = backgroundColor;
            IncrementButton.style.borderTopLeftRadius = 0;
            IncrementButton.style.borderTopRightRadius = 0;
            IncrementButton.style.borderBottomRightRadius = 0;
            IncrementButton.style.backgroundSize = buttonSize;
            IncrementButton.style.unityFontStyleAndWeight = FontStyle.Bold;
            IncrementButton.style.fontSize = 15;
            IncrementButton.focusable = false;
            IncrementButton.clicked += IncrementCount;

            DecrementButton = new Button() { text = "-" };
            DecrementButton.style.marginTop = 0;
            DecrementButton.style.marginRight = 16;
            DecrementButton.style.marginLeft = 0;
            DecrementButton.style.marginBottom = 5;
            DecrementButton.style.paddingLeft = 8;
            DecrementButton.style.paddingRight = 8;
            DecrementButton.style.borderTopColor = backgroundColor;
            DecrementButton.style.borderBottomColor = backgroundColor;
            DecrementButton.style.borderLeftColor = backgroundColor;
            DecrementButton.style.borderRightColor = backgroundColor;
            DecrementButton.style.borderTopLeftRadius = 0;
            DecrementButton.style.borderTopRightRadius = 0;
            DecrementButton.style.borderBottomLeftRadius = 0;
            DecrementButton.style.backgroundSize = buttonSize;
            DecrementButton.style.unityFontStyleAndWeight = FontStyle.Bold;
            DecrementButton.style.fontSize = 15;
            DecrementButton.focusable = false;
            DecrementButton.clicked += DecrementCount;

            m_ButtonContainer.Add(IncrementButton);
            m_ButtonContainer.Add(DecrementButton);
            Add(m_ButtonContainer);
        }

        public delegate void OnIncrementCount(int count);
        public OnIncrementCount OnIncrementCallback;
        public delegate void OnDecrementCount(int count);
        public OnDecrementCount OnDecrementCallback;

        public void IncrementCount()
        {
            m_Count++;
            if (m_Count > m_MaximumCount)
                m_Count = m_MaximumCount;
            OnIncrementCallback(m_Count);
        }
        public void DecrementCount()
        {
            m_Count--;
            if (m_Count < 0)
                m_Count = 0;
            OnDecrementCallback(m_Count);
        }
    }
}
