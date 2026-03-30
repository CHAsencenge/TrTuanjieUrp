#if UNITY_IOS
using System;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

public class MetalFXPostProcessBuild
{
    /// <summary>
    /// If iOS sdk version >= 16.0, we must add MetalFX.framework to the generated Xcode project.
    /// Even if MetalFX is not enabled at build time, users might switch to MetalFX at runtime.
    /// </summary>
    [PostProcessBuild]
    public static void OnMetalFXPostProcessBuild(BuildTarget buildTarget, string pathToBuiltProject)
    {
        if (buildTarget != BuildTarget.iOS)
            return;

        // Check iOS sdk version
        if (string.IsNullOrEmpty(PlayerSettings.iOS.targetOSVersionString) ||
            Version.TryParse(PlayerSettings.iOS.targetOSVersionString, out var version) && version < new Version(16, 0))
            return;

        // Initialize PBXProject
        string projectPath = PBXProject.GetPBXProjectPath(pathToBuiltProject);
        PBXProject pbxProject = new PBXProject();
        pbxProject.ReadFromFile(projectPath);

        // Add MetalFX framework to TuanjieFramework target
        pbxProject.AddFrameworkToProject(pbxProject.GetUnityFrameworkTargetGuid(), "MetalFX.framework", false);

        // Apply changes to the pbxproj file
        pbxProject.WriteToFile(projectPath);
    }
}
#endif
