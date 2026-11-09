// Corner glow: when a hot corner fires, a soft light plays in that corner.
// Ported from the jenkins-menubar app (HotCornerGlow / HotCornerGlowView / HotCornerGlowPanel), single-module version.

import Cocoa
import SwiftUI

extension Corner {
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

// MARK: - Glow settings as data

enum GlowStyle: String, CaseIterable {
    case glow, pulse, ripple

    var title: String {
        switch self {
        case .glow: return "Glow"
        case .pulse: return "Pulse"
        case .ripple: return "Ripple"
        }
    }
}

enum GlowSize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    /// how far the glow reaches from the corner, in points
    var points: Double {
        switch self {
        case .small: return 200
        case .medium: return 320
        case .large: return 480
        }
    }
}

/// The system accent, a preset, or the user's own as `RRGGBB` hex text.
enum GlowColor: Hashable {
    case accent, white, purple, pink, orange, green
    case custom(hex: String)

    static let presets: [GlowColor] = [.accent, .white, .purple, .pink, .orange, .green]

    var title: String {
        switch self {
        case .custom: return "Custom"
        default: return storedText.capitalized
        }
    }

    var storedText: String {
        switch self {
        case .accent: return "accent"
        case .white: return "white"
        case .purple: return "purple"
        case .pink: return "pink"
        case .orange: return "orange"
        case .green: return "green"
        case .custom(let hex): return "#" + hex
        }
    }

    init(storedText text: String) {
        switch text {
        case "white": self = .white
        case "purple": self = .purple
        case "pink": self = .pink
        case "orange": self = .orange
        case "green": self = .green
        default:
            if text.hasPrefix("#"), let hex = Self.normalizedHex(String(text.dropFirst())) {
                self = .custom(hex: hex)
            } else {
                self = .accent
            }
        }
    }

    static func normalizedHex(_ text: String) -> String? {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return digits.uppercased()
    }

    typealias RGB = (red: Double, green: Double, blue: Double)

    var rgb: RGB {
        switch self {
        case .accent:
            let c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        case .white: return (1.00, 1.00, 1.00)
        case .purple: return (0.62, 0.36, 0.98)
        case .pink: return (1.00, 0.34, 0.62)
        case .orange: return (1.00, 0.58, 0.16)
        case .green: return (0.22, 0.84, 0.46)
        case .custom(let hex):
            let v = UInt32(hex, radix: 16) ?? 0
            return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
    }

    var swiftUIColor: Color {
        let c = rgb
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// `RRGGBB` of a SwiftUI color, for the custom picker.
    static func hex(of color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        func byte(_ x: CGFloat) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

struct GlowConfig: Equatable {
    var enabled = true
    var color = GlowColor.accent
    /// the color the glow blends into further out; nil for a single color
    var secondary: GlowColor?
    var style = GlowStyle.glow
    var size = GlowSize.medium
    /// how far the corner color reaches before the second takes over, 0.1…0.9
    var balance = 0.5
    /// a bright (white-hot) center; off keeps the color's own hue all the way in
    var whiteCore = true
    var duration = 0.8
    var opacity = 0.8

    static let durationRange: ClosedRange<Double> = 0.4...2.0
    static let balanceRange: ClosedRange<Double> = 0.1...0.9
    static let opacityRange: ClosedRange<Double> = 0.2...1.0
}

// MARK: - The light

/// Plays once from the moment it appears, over `glow.duration`, and draws nothing afterwards.
struct GlowView: View {
    let corner: Corner
    let glow: GlowConfig
    let side: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            GlowArt(
                corner: corner, glow: glow, progress: timeline.date.timeIntervalSince(start) / glow.duration,
                reduceMotion: reduceMotion)
        }
        .frame(width: side, height: side)
        .onAppear { start = Date() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame of the glow; `progress` 0 is the start, 1 the end.
private struct GlowArt: View {
    let corner: Corner
    let glow: GlowConfig
    let progress: Double
    var reduceMotion = false

    var body: some View {
        let inner = glow.color.rgb
        let rgb: Pal = (
            inner, (glow.secondary ?? glow.color).rgb, glow.whiteCore ? Self.mix(inner, with: 0.4) : inner, glow.balance)
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: corner.isLeft ? 0 : size.width, y: corner.isTop ? 0 : size.height)
            var layer = context
            layer.opacity = glow.opacity
            // Adding light saturates toward white; plain layering keeps the hue.
            layer.blendMode = glow.whiteCore ? .plusLighter : .normal
            Self.draw(
                in: &layer, side: side, origin: origin, rgb: rgb, style: glow.style,
                progress: min(1, max(0, progress)), reduceMotion: reduceMotion)
        }
        .allowsHitTesting(false)
    }

    private typealias RGB = GlowColor.RGB
    private typealias Pal = (inner: RGB, outer: RGB, core: RGB, balance: Double)

    private static func draw(
        in context: inout GraphicsContext, side: CGFloat, origin: CGPoint, rgb: Pal, style: GlowStyle,
        progress p: Double, reduceMotion: Bool
    ) {
        if reduceMotion {
            let intensity = smoothstep(0, 0.25, p) * (1 - smoothstep(0.3, 1, p))
            bloom(&context, side: side, origin: origin, rgb: rgb, radius: 0.8, intensity: intensity)
            return
        }
        switch style {
        case .glow:
            let rise = smoothstep(0, 0.14, p)
            let fall = 1 - easeInOut((p - 0.22) / 0.78)
            let radius = 0.45 + 0.55 * easeOut(p)
            bloom(&context, side: side, origin: origin, rgb: rgb, radius: radius, intensity: rise * pow(max(0, fall), 1.4))
        case .pulse:
            let first = exp(-pow((p - 0.24) / 0.12, 2))
            let second = 0.8 * exp(-pow((p - 0.64) / 0.14, 2))
            let beat = min(1, first + second) * smoothstep(0, 0.05, p)
            bloom(&context, side: side, origin: origin, rgb: rgb, radius: 0.5 + 0.38 * beat + 0.08 * p, intensity: beat)
        case .ripple:
            let source = smoothstep(0, 0.1, p) * (1 - smoothstep(0.1, 0.65, p))
            bloom(&context, side: side, origin: origin, rgb: rgb, radius: 0.34 + 0.2 * easeOut(p), intensity: source)
            for delay in [0.0, 0.17, 0.34] {
                let q = (p - delay) / 0.56
                guard q > 0, q < 1 else { continue }
                let radius = Double(side) * 0.86 * easeOut(q)
                let width = Double(side) * (0.06 + 0.07 * q)
                let alpha = pow(1 - q, 1.3) * smoothstep(0, 0.08, q)
                ring(&context, side: side, origin: origin, rgb: blend(rgb.inner, rgb.outer, q), radius: radius, width: width, alpha: alpha)
            }
        }
    }

    /// Three layers: wide and soft, tighter, and a small hot core that leans to white.
    private static func bloom(
        _ context: inout GraphicsContext, side: CGFloat, origin: CGPoint, rgb: Pal, radius: Double, intensity: Double
    ) {
        guard intensity > 0.002 else { return }
        let reach = Double(side) * radius
        let hot = rgb.core
        // Wide layer: the corner color near the corner, turning into the outer color further out.
        fill(&context, side: side, origin: origin, radius: reach,
            stops: softStops(rgb.inner, rgb.outer, peak: 0.8 * intensity, from: rgb.balance - 0.45, to: rgb.balance + 0.1))
        fill(&context, side: side, origin: origin, radius: reach * 0.55,
            stops: softStops(rgb.inner, rgb.outer, peak: 0.85 * intensity, from: rgb.balance, to: rgb.balance + 0.8))
        fill(&context, side: side, origin: origin, radius: reach * 0.22, stops: softStops(hot, peak: 0.8 * intensity))
    }

    private static func ring(
        _ context: inout GraphicsContext, side: CGFloat, origin: CGPoint, rgb: RGB, radius: Double, width: Double,
        alpha: Double
    ) {
        guard alpha > 0.002, radius > 0 else { return }
        let outer = radius + width
        let samples = 16
        let stops = (0...samples).map { index -> Gradient.Stop in
            let x = -1 + 2 * Double(index) / Double(samples)
            let shape = pow(cos(x * .pi / 2), 2)
            return Gradient.Stop(
                color: color(mix(rgb, with: 0.3 * shape), alpha: alpha * shape),
                location: max(0, (radius + x * width) / outer))
        }
        fill(&context, side: side, origin: origin, radius: outer, stops: stops)
    }

    private static func fill(
        _ context: inout GraphicsContext, side: CGFloat, origin: CGPoint, radius: Double, stops: [Gradient.Stop]
    ) {
        let rect = CGRect(x: origin.x - side, y: origin.y - side, width: side * 2, height: side * 2)
        context.fill(
            Path(rect),
            with: .radialGradient(Gradient(stops: stops), center: origin, startRadius: 0, endRadius: CGFloat(radius)))
    }

    /// A falloff whose color goes from `inner` at the center to `outer` between `from` and `to` (0…1 of the radius).
    private static func softStops(_ inner: RGB, _ outer: RGB, peak: Double, from: Double, to: Double) -> [Gradient.Stop] {
        let samples = 14
        return (0...samples).map { index in
            let x = Double(index) / Double(samples)
            let rgb = blend(inner, outer, smoothstep(from, to, x))
            return Gradient.Stop(color: color(rgb, alpha: peak * pow(cos(x * .pi / 2), 2.0)), location: x)
        }
    }

    private static func softStops(_ rgb: RGB, peak: Double) -> [Gradient.Stop] {
        let samples = 14
        return (0...samples).map { index in
            let x = Double(index) / Double(samples)
            return Gradient.Stop(color: color(rgb, alpha: peak * pow(cos(x * .pi / 2), 2.0)), location: x)
        }
    }

    private static func color(_ rgb: RGB, alpha: Double) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: alpha)
    }

    private static func blend(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t)
    }

    private static func mix(_ rgb: RGB, with white: Double) -> RGB {
        (rgb.red + (1 - rgb.red) * white, rgb.green + (1 - rgb.green) * white, rgb.blue + (1 - rgb.blue) * white)
    }

    private static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(1, max(0, t)), 2.6) }

    private static func easeInOut(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - The panel

/// A transparent, click-through panel in a display's corner that plays the glow once and closes itself. It never
/// takes focus, floats above everything and shows on every Space and over full-screen apps.
final class GlowPanel: NSPanel {
    private static var current: GlowPanel?

    /// - Parameters:
    ///   - screen: the display's frame in global coordinates (bottom-left origin)
    static func show(at corner: Corner, screen: CGRect, glow: GlowConfig) {
        current?.close()
        let side = min(CGFloat(glow.size.points), screen.width, screen.height)
        let frame = CGRect(
            x: corner.isLeft ? screen.minX : screen.maxX - side,
            y: corner.isTop ? screen.maxY - side : screen.minY, width: side, height: side)
        let panel = GlowPanel(frame: frame)
        let hosting = NSHostingView(rootView: GlowView(corner: corner, glow: glow, side: side))
        hosting.sizingOptions = []
        panel.contentView = hosting
        current = panel
        panel.orderFrontRegardless()
        let seconds = glow.duration + 0.15
        Task { [weak panel] in
            try? await Task.sleep(for: .seconds(seconds))
            panel?.close()
        }
    }

    private init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Keeps the glow where it was put, even in the menu bar's area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func close() {
        if Self.current === self { Self.current = nil }
        super.close()
    }
}
