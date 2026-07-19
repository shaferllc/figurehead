import Foundation
import CoreGraphics

// MARK: - Color

/// Plain sRGB color that is Codable and Sendable (no AppKit dependency).
struct RGBA: Codable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Dark-mode twin for user-picked colors: keep the hue, drop the
    /// brightness hard, and nudge saturation up so it does not go muddy.
    func darkened() -> RGBA {
        var (h, s, v) = RGBA.rgbToHSV(r, g, b)
        v *= 0.34
        s = min(1, s * 1.15 + 0.06)
        let (nr, ng, nb) = RGBA.hsvToRGB(h, s, v)
        return RGBA(nr, ng, nb, a)
    }

    static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }

    static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60:   (r, g, b) = (c, x, 0)
        case ..<120:  (r, g, b) = (x, c, 0)
        case ..<180:  (r, g, b) = (0, c, x)
        case ..<240:  (r, g, b) = (0, x, c)
        case ..<300:  (r, g, b) = (x, 0, c)
        default:      (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

// MARK: - Backdrop

enum GradientShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear, radial
    var id: String { rawValue }
    var label: String { self == .linear ? "Linear" : "Radial" }
}

/// A named gradient with an explicit dark-mode counterpart.
struct GradientPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let lightA: RGBA, lightB: RGBA
    let darkA: RGBA, darkB: RGBA

    static let all: [GradientPreset] = [
        GradientPreset(id: "lagoon", name: "Lagoon",
                       lightA: RGBA(0.49, 0.83, 0.94), lightB: RGBA(0.23, 0.42, 0.88),
                       darkA: RGBA(0.05, 0.17, 0.33), darkB: RGBA(0.02, 0.06, 0.17)),
        GradientPreset(id: "dawn", name: "Dawn",
                       lightA: RGBA(0.99, 0.82, 0.69), lightB: RGBA(0.93, 0.45, 0.58),
                       darkA: RGBA(0.30, 0.10, 0.22), darkB: RGBA(0.11, 0.04, 0.13)),
        GradientPreset(id: "meadow", name: "Meadow",
                       lightA: RGBA(0.76, 0.94, 0.77), lightB: RGBA(0.22, 0.62, 0.47),
                       darkA: RGBA(0.04, 0.22, 0.16), darkB: RGBA(0.01, 0.09, 0.08)),
        GradientPreset(id: "violet", name: "Violet",
                       lightA: RGBA(0.86, 0.81, 0.99), lightB: RGBA(0.49, 0.32, 0.89),
                       darkA: RGBA(0.16, 0.10, 0.33), darkB: RGBA(0.07, 0.03, 0.16)),
        GradientPreset(id: "ember", name: "Ember",
                       lightA: RGBA(0.99, 0.86, 0.60), lightB: RGBA(0.93, 0.47, 0.26),
                       darkA: RGBA(0.26, 0.12, 0.06), darkB: RGBA(0.11, 0.04, 0.03)),
        GradientPreset(id: "graphite", name: "Graphite",
                       lightA: RGBA(0.93, 0.94, 0.96), lightB: RGBA(0.66, 0.70, 0.77),
                       darkA: RGBA(0.17, 0.18, 0.21), darkB: RGBA(0.06, 0.07, 0.09)),
    ]

    static func find(_ id: String) -> GradientPreset { all.first { $0.id == id } ?? all[0] }
}

enum BackdropKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case preset, custom, solid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .preset: "Presets"
        case .custom: "Custom"
        case .solid: "Solid"
        }
    }
}

struct BackdropSettings: Codable, Hashable, Sendable {
    var kind: BackdropKind = .preset
    var presetID: String = "lagoon"
    var customA = RGBA(0.98, 0.75, 0.55)
    var customB = RGBA(0.75, 0.25, 0.55)
    var solid = RGBA(0.93, 0.93, 0.95)
    var shape: GradientShape = .linear
    var grain = false
    var paddingFraction: Double = 0.10

    /// The two backdrop colors for the requested appearance
    /// (identical pair for solid fills).
    func resolvedColors(dark: Bool) -> (RGBA, RGBA) {
        switch kind {
        case .preset:
            let p = GradientPreset.find(presetID)
            return dark ? (p.darkA, p.darkB) : (p.lightA, p.lightB)
        case .custom:
            return dark ? (customA.darkened(), customB.darkened()) : (customA, customB)
        case .solid:
            let c = dark ? solid.darkened() : solid
            return (c, c)
        }
    }
}

// MARK: - Caption

enum CaptionWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, regular, medium, semibold, bold, heavy, black
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CaptionPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case above, below
    var id: String { rawValue }
    var label: String { self == .above ? "Above" : "Below" }
}

struct CaptionSettings: Codable, Hashable, Sendable {
    var text: String = ""
    var weight: CaptionWeight = .semibold
    var placement: CaptionPlacement = .above
    /// Font size as a fraction of canvas height.
    var sizeFraction: Double = 0.045
}

// MARK: - Canvas

struct CanvasSpec: Codable, Hashable, Sendable {
    var width: Int = 2560
    var height: Int = 1600
}

struct CanvasPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let width: Int
    let height: Int

    static let all: [CanvasPreset] = [
        CanvasPreset(id: "2560", name: "2560 × 1600", width: 2560, height: 1600),
        CanvasPreset(id: "1440", name: "1440 × 900", width: 1440, height: 900),
        CanvasPreset(id: "appstore", name: "App Store 2880 × 1800", width: 2880, height: 1800),
        CanvasPreset(id: "og", name: "Twitter / OG 1200 × 630", width: 1200, height: 630),
    ]
}

// MARK: - Layer

/// One captured window in the composition. Layers are ordered back → front.
struct ShotLayer: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = "Window"

    /// PNG file names inside the project bundle (set on save).
    var lightFile: String?
    var darkFile: String?

    /// Window IDs remembered from capture so "Recapture" can re-grab the
    /// same window (valid while that window still exists).
    var sourceWindowID: UInt32?
    var darkSourceWindowID: UInt32?

    var scale: Double = 1.0            // multiplier on the fitted size
    var offsetX: Double = 0            // fraction of canvas width, + = right
    var offsetY: Double = 0            // fraction of canvas height, + = down
    var rotation: Double = 0           // degrees, clockwise, ±6
    var shadowRadius: Double = 36      // px at 1x canvas scale
    var shadowOpacity: Double = 0.40
    var shadowOffsetY: Double = 18     // px at 1x, + = down
    var cornerRadius: Double = 14      // px at 1x
}

// MARK: - Project

struct Project: Codable, Hashable, Sendable {
    var canvas = CanvasSpec()
    var backdrop = BackdropSettings()
    var caption = CaptionSettings()
    var layers: [ShotLayer] = []
}

// MARK: - Arrangements

enum Arrangement: String, CaseIterable, Identifiable, Sendable {
    case single, duo, fan
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: "Single"
        case .duo: "Duo"
        case .fan: "Fan"
        }
    }
    var layerCount: Int {
        switch self {
        case .single: 1
        case .duo: 2
        case .fan: 3
        }
    }

    /// (scale, offsetX, offsetY, rotation) back → front.
    var placements: [(Double, Double, Double, Double)] {
        switch self {
        case .single:
            [(1.0, 0, 0, 0)]
        case .duo:
            [(0.84, -0.11, -0.05, -2.5),
             (1.0, 0.07, 0.04, 0)]
        case .fan:
            [(0.76, -0.17, -0.04, -5),
             (0.80, 0.17, -0.03, 5),
             (1.0, 0, 0.04, 0)]
        }
    }
}
