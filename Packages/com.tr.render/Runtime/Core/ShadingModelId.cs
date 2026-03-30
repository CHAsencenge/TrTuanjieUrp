namespace Game.Rendering
{
    /// <summary>
    /// Identifies the shading model for deferred GBuffer encoding.
    /// Stored in 4 bits of GBuffer0.a (range 0-15).
    /// Modeled after UE5's shading model ID system.
    /// </summary>
    public enum ShadingModelId : byte
    {
        /// <summary>Standard PBR (metallic/roughness workflow).</summary>
        DefaultLit = 0,

        /// <summary>Subsurface scattering material (skin, wax, etc.).</summary>
        Subsurface = 1,

        /// <summary>Clear coat layer over base material (car paint, lacquer).</summary>
        ClearCoat = 2,

        /// <summary>Two-sided foliage with backface translucency.</summary>
        TwoSidedFoliage = 3,

        // 4-14: Reserved for future shading models

        /// <summary>Unlit material, emissive only, no lighting evaluation.</summary>
        Unlit = 15
    }

    /// <summary>
    /// Per-pixel material flags stored in 4 bits of GBuffer0.a.
    /// Combined with ShadingModelId to form a packed byte.
    /// </summary>
    [System.Flags]
    public enum MaterialFlags : byte
    {
        /// <summary>No special flags.</summary>
        None = 0,

        /// <summary>Object does not receive shadows.</summary>
        ReceiveShadowsOff = 1 << 0,

        /// <summary>Specular highlights disabled.</summary>
        SpecularHighlightsOff = 1 << 1,

        /// <summary>Uses specular workflow instead of metallic.</summary>
        SpecularSetup = 1 << 2,

        // Bit 3 reserved for future use
    }
}
