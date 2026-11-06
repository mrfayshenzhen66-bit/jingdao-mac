//  Adjustments.swift — Layer 2: adjustments to the print output, client-side.
//
//  These operate on the encoded print output the way a scan of a print is
//  adjusted afterwards (frontend SPEC §3.1). They live entirely in the Metal
//  shader (`Shaders.metal`, `layer2`) and cost < 1 ms; nothing here reaches
//  the service. Order of operations is fixed and matches the shader:
//
//      white balance → exposure/contrast/brightness → highlights/shadows
//      → black/white point → saturation → colour balance → curves → vignette
//
//  Zero is "nothing applied" for every field, so a fresh image reads as the
//  pure simulation, and `enabled = false` bypasses the whole layer.

import Foundation
import simd

struct ColorZone: Codable, Equatable, Sendable {
    /// Hue angle in degrees, saturation 0…1 (wheel radius), luminance −1…1.
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0
    var isNeutral: Bool { saturation == 0 && luminance == 0 }

    /// The RGB offset this zone applies, in the shader's units.
    var rgbOffset: SIMD3<Float> {
        let h = hue * .pi / 180
        // Hue on the wheel → unit RGB direction (0° = red, 120° = green, 240° = blue).
        let r = cos(h), g = cos(h - 2 * .pi / 3), b = cos(h + 2 * .pi / 3)
        let s = Float(saturation) * 0.25
        return SIMD3<Float>(Float(r), Float(g), Float(b)) * s
    }
}

struct ColorBalance: Codable, Equatable, Sendable {
    var master = ColorZone()
    var shadows = ColorZone()
    var midtones = ColorZone()
    var highlights = ColorZone()
    var isNeutral: Bool { master.isNeutral && shadows.isNeutral && midtones.isNeutral && highlights.isNeutral }
}

struct Vignette: Codable, Equatable, Sendable {
    var amount: Double = 0      // −100…100, negative darkens the corners
    var midpoint: Double = 50   // 0…100, radius at which falloff starts
    var isNeutral: Bool { amount == 0 }
}

/// One of eight hue bands (景到). hue −100…100 (→ ±30°), saturation and
/// luminance −100…100.
struct HSLBand: Codable, Equatable, Sendable {
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0
}

struct HSLAdjustments: Codable, Equatable, Sendable {
    static let bandCount = 8
    var bands = [HSLBand](repeating: HSLBand(), count: HSLAdjustments.bandCount)
    var isNeutral: Bool { bands.allSatisfy { $0 == HSLBand() } }
    subscript(index: Int) -> HSLBand {
        get { bands.indices.contains(index) ? bands[index] : HSLBand() }
        set {
            if bands.count < Self.bandCount { bands += Array(repeating: HSLBand(), count: Self.bandCount - bands.count) }
            bands[index] = newValue
        }
    }
}

struct Adjustments: Codable, Equatable, Sendable {
    var enabled: Bool = true
    // White balance, post-print (Capture One's model, but as an offset).
    var temperature: Double = 0    // −100…100, blue ↔ amber
    var tint: Double = 0           // −100…100, green ↔ magenta
    // Exposure group (Capture One's four).
    var exposure: Double = 0       // stops, −3…3
    var contrast: Double = 0       // −50…50
    var brightness: Double = 0     // −50…50
    var saturation: Double = 0     // −100…100
    // Tone-region recovery.
    var highlights: Double = 0     // −100…100
    var shadows: Double = 0        // −100…100
    var blackPoint: Double = 0     // 0…50  (percent of range lifted to black)
    var whitePoint: Double = 0     // 0…50
    var curves = CurveSet()
    var colorBalance = ColorBalance()
    var vignette = Vignette()
    /// Eight-band HSL (景到). Applied after Layer 2 by the `hslAdjust` kernel
    /// on the canvas and in export; masks do not carry it.
    var hsl = HSLAdjustments()

    static let `default` = Adjustments()

    private enum CodingKeys: String, CodingKey {
        case enabled, temperature, tint, exposure, contrast, brightness, saturation
        case highlights, shadows, blackPoint, whitePoint, curves, colorBalance, vignette, hsl
    }
    init() {}
    init(enabled: Bool) { self.enabled = enabled }
    /// Records written before a field existed keep decoding: every member
    /// falls back to its neutral default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Adjustments()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? d.temperature
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? d.tint
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? d.exposure
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? d.contrast
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? d.brightness
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? d.highlights
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? d.shadows
        blackPoint = try c.decodeIfPresent(Double.self, forKey: .blackPoint) ?? d.blackPoint
        whitePoint = try c.decodeIfPresent(Double.self, forKey: .whitePoint) ?? d.whitePoint
        curves = try c.decodeIfPresent(CurveSet.self, forKey: .curves) ?? d.curves
        colorBalance = try c.decodeIfPresent(ColorBalance.self, forKey: .colorBalance) ?? d.colorBalance
        vignette = try c.decodeIfPresent(Vignette.self, forKey: .vignette) ?? d.vignette
        hsl = try c.decodeIfPresent(HSLAdjustments.self, forKey: .hsl) ?? d.hsl
    }
    var isNeutral: Bool { self == Adjustments(enabled: enabled) }

    /// The per-frame uniform block the shader reads. Computed on the CPU once
    /// per change, not per pixel.
    var uniforms: Layer2Uniforms {
        // The tone block is `Layer2Uniforms.tone` — the *same* function every
        // mask uses (`Model/Mask.swift`). Temperature and tint become channel
        // gains there, ±100 → roughly ±0.18 on the opposing channels, which
        // is the visual range of a scan white-balance correction rather than
        // a scene one. Sharing it is what makes "+1 stop" mean one stop
        // whether the slider was the global one or a mask's.
        var u = Layer2Uniforms.tone(temperature: temperature, tint: tint, exposure: exposure,
                                    contrast: contrast, brightness: brightness, saturation: saturation,
                                    highlights: highlights, shadows: shadows,
                                    blackPoint: blackPoint, whitePoint: whitePoint)
        u.enabled = enabled ? 1 : 0
        u.cbMaster = colorBalance.master.rgbOffset
        u.cbShadows = colorBalance.shadows.rgbOffset
        u.cbMidtones = colorBalance.midtones.rgbOffset
        u.cbHighlights = colorBalance.highlights.rgbOffset
        u.cbLum = SIMD4<Float>(Float(colorBalance.master.luminance), Float(colorBalance.shadows.luminance),
                               Float(colorBalance.midtones.luminance), Float(colorBalance.highlights.luminance)) * 0.25
        u.vignetteAmount = Float(vignette.amount) / 100
        u.vignetteMidpoint = Float(vignette.midpoint) / 100
        u.curvesActive = curves.isIdentity ? 0 : 1
        return u
    }
}

/// Must match `Layer2Uniforms` in Shaders.metal field for field and in order.
struct Layer2Uniforms: Sendable {
    var wbGain = SIMD3<Float>(repeating: 1)
    var exposureGain: Float = 1
    var cbMaster = SIMD3<Float>(repeating: 0)
    var contrast: Float = 0
    var cbShadows = SIMD3<Float>(repeating: 0)
    var brightness: Float = 0
    var cbMidtones = SIMD3<Float>(repeating: 0)
    var saturation: Float = 1
    var cbHighlights = SIMD3<Float>(repeating: 0)
    var highlights: Float = 0
    var cbLum = SIMD4<Float>(repeating: 0)
    var shadows: Float = 0
    var blackPoint: Float = 0
    var whitePoint: Float = 0
    var vignetteAmount: Float = 0
    var vignetteMidpoint: Float = 0.5
    /// Encoded mid-grey (linear 0.18) in the working space — RFC-018 D1's
    /// pivot. See `Layer2Uniforms.tone` for the two constants and why the
    /// default is the ROMM one.
    var midGrey: Float = Layer2Uniforms.proPhotoMidGrey
    var curvesActive: UInt32 = 0
    var enabled: UInt32 = 1
    /// RFC-028: read the source through the Cineon → ProPhoto table first.
    /// Set by the renderer for a Digital Intermediate, never by an edit.
    var inputDecode: UInt32 = 0

    /// `pow(0.18, 1/1.8)` — mid-grey through ROMM γ1.8, the working space's
    /// own curve since RFC-018. The number `layer2Tone` pivots on.
    ///
    /// Kept beside `srgbMidGrey` rather than inlined because the *pair* is the
    /// decision: D1 says the pivot follows the encoding, so a future move to
    /// another working space is a swap of which constant is the default, not a
    /// hunt for literals.
    static let proPhotoMidGrey: Float = 0.3857
    /// `1.055·0.18^(1/2.4) − 0.055` — the same through an sRGB-like curve,
    /// which is what Display P3 has and what this code pivoted on by accident
    /// until RFC-018.
    static let srgbMidGrey: Float = 0.4614
}
