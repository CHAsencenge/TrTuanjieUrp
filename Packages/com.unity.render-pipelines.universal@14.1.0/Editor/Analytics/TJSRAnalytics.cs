using UnityEngine.Analytics;
using UnityEngine.Rendering;

namespace UnityEditor.Rendering.Universal.Analytics
{
    public class TJSRAnalytics
    {
        const string k_VendorKey = "unity.tjsr";
        const string k_EventName = "tjsrEvent";
        const int k_Version = 1;

        class TJSRData
        {
            internal const int k_MaxEventsPerHour = 1000;
            internal const int k_MaxNumberOfElements = 1000;
            public string action;
            public int quality;
            public float contrastAdaptiveSharpening;
        }

        public static void SendTJSREvent(string action, int quality, float contrastAdaptiveSharpening)
        {
            if (!EditorAnalytics.enabled || EditorAnalytics.RegisterEventWithLimit(k_EventName, TJSRData.k_MaxEventsPerHour, TJSRData.k_MaxNumberOfElements, k_VendorKey, k_Version) != AnalyticsResult.Ok)
                return;

            using (GenericPool<TJSRData>.Get(out var data))
            {
                data.action = action;
                data.quality = quality;
                data.contrastAdaptiveSharpening = contrastAdaptiveSharpening;
                EditorAnalytics.SendEventWithLimit(k_EventName, data, k_Version);
            }
        }

    }
}
