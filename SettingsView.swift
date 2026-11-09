// The settings window: a screen mockup of the four corners, the actions of the selected corner (corner only, or with
// ⌘ ⌥ ⌃ ⇧ held), and the corner glow.

import Cocoa
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let shortcuts: [String]
    /// plays the glow on the real screen, in the given corner
    let testOnScreen: (Corner) -> Void

    @State private var selected = Corner.topLeft
    @State private var previewToken = 0
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Toggle("Enabled", isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
                    Toggle("Open at Login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                    if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
                }

            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: loginError == nil ? 165 : 195)
            if settings.enabled {
            mockup.padding(.horizontal, 20)
            Form {
                Section {
                    Picker(selection: Binding(
                        get: { nearestDelay(settings.delay(for: selected)) }, set: { settings.setDelay($0, for: selected) })
                    ) {
                        ForEach(delayChoices, id: \.value) { Text($0.label).tag($0.value) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delay")
                            Text("How long the pointer rests in the corner first").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Modifier.allCases, id: \.self) { mod in
                        HStack(spacing: 10) {
                            Image(systemName: mod.symbol)
                                .frame(width: 28, height: 28)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            Text(mod.title)
                            Spacer()
                            ActionMenu(
                                action: Binding(
                                    get: { settings.action(for: selected, mod) },
                                    set: { settings.setAction($0, for: selected, mod) }),
                                shortcuts: shortcuts)
                        }
                    }
                } header: {
                    Text("\(selected.title) Corner")
                } footer: {
                    Text("Hold ⌘, ⌥, ⌃ or ⇧ as the pointer reaches the corner to run its other action. Nothing fires while a mouse button is down. Corners between two displays don't count.")
                }

                Section("Corner Glow") {
                    Toggle("Glow when a corner fires", isOn: glow(\.enabled))
                    if settings.glow.enabled {
                        LabeledContent("Corner Color") { ColorSwatches(selection: glow(\.color).optional) }
                        LabeledContent("Blend Into") { ColorSwatches(selection: glow(\.secondary), allowNone: true) }
                        if settings.glow.secondary != nil {
                            LabeledContent("Corner Color Reach") {
                                HStack {
                                    Slider(value: glow(\.balance), in: GlowConfig.balanceRange, step: 0.05)
                                    Text("\(Int((settings.glow.balance * 100).rounded())) %").monospacedDigit().frame(width: 44)
                                }
                            }
                        }
                        Toggle("Bright center", isOn: glow(\.whiteCore))
                        Picker("Animation", selection: glow(\.style)) {
                            ForEach(GlowStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("Size", selection: glow(\.size)) {
                            ForEach(GlowSize.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        LabeledContent("Duration") {
                            HStack {
                                Slider(value: glow(\.duration), in: GlowConfig.durationRange, step: 0.1)
                                Text(String(format: "%.1f s", settings.glow.duration)).monospacedDigit().frame(width: 44)
                            }
                        }
                        LabeledContent("Opacity") {
                            HStack {
                                Slider(value: glow(\.opacity), in: GlowConfig.opacityRange, step: 0.05)
                                Text("\(Int((settings.glow.opacity * 100).rounded())) %").monospacedDigit().frame(width: 44)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Replay") { previewToken += 1 }
                            Button("Test on Screen") { testOnScreen(selected) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            }
        }
        .frame(width: 560, height: settings.enabled ? 800 : 200, alignment: .top)
    }

    // MARK: Mockup

    private var mockup: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.30, blue: 0.82), Color(red: 0.26, green: 0.12, blue: 0.46), Color(red: 0.56, green: 0.20, blue: 0.46)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            if settings.glow.enabled {
                GlowView(corner: selected, glow: settings.glow, side: 170)
                    .id(previewToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(of: selected))
            }
            VStack {
                menuBar
                Spacer()
                dock
            }
            VStack {
                HStack(alignment: .top) { card(.topLeft); Spacer(minLength: 8); card(.topRight) }
                Spacer()
                HStack(alignment: .bottom) { card(.bottomLeft); Spacer(minLength: 8); card(.bottomRight) }
            }
            .padding(.horizontal, 12).padding(.top, 40).padding(.bottom, 12)
        }
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }

    private var menuBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo").font(.caption)
            ForEach([34, 22, 28], id: \.self) { Capsule().fill(.white.opacity(0.7)).frame(width: CGFloat($0), height: 6) }
            Spacer()
            ForEach([12, 12, 34], id: \.self) { Capsule().fill(.white.opacity(0.7)).frame(width: CGFloat($0), height: 6) }
        }
        .padding(.horizontal, 12).frame(height: 26).background(.black.opacity(0.18))
        .foregroundStyle(.white)
    }

    private var dock: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: 12, height: 12) }
        }
        .padding(7).background(.black.opacity(0.18), in: Capsule()).padding(.bottom, 10)
    }

    private func card(_ corner: Corner) -> some View {
        let plain = settings.action(for: corner, .plain)
        let delay = settings.delay(for: corner)
        let extras = Modifier.allCases.filter { $0 != .plain && settings.action(for: corner, $0) != .none }
        let isRight = !corner.isLeft
        return VStack(alignment: isRight ? .trailing : .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: plain.symbol)
                Text(plain.title).fontWeight(.semibold).lineLimit(1)
                Text(delay == 0 ? "Instant" : String(format: "%g s", delay))
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            ForEach(extras, id: \.self) { mod in
                Text("\(mod.glyph) \(settings.action(for: corner, mod).title)")
                    .font(.caption).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.14), in: Capsule())
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: 215, alignment: isRight ? .trailing : .leading)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: selected == corner ? 2.5 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { selected = corner; previewToken += 1 }
    }

    // MARK: Pieces

    private func glow<T>(_ key: WritableKeyPath<GlowConfig, T>) -> Binding<T> {
        Binding(
            get: { settings.glow[keyPath: key] },
            set: {
                var g = settings.glow
                g[keyPath: key] = $0
                settings.glow = g
                previewToken += 1
            })
    }

    private func alignment(of corner: Corner) -> Alignment {
        switch corner {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private func nearestDelay(_ value: Double) -> Double {
        delayChoices.min { abs($0.value - value) < abs($1.value - value) }?.value ?? 0.15
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change Open at Login: \(error.localizedDescription)"
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// A menu to pick what a corner does: a system action, one of the user's shortcuts, or nothing.
struct ActionMenu: View {
    @Binding var action: CornerAction
    let shortcuts: [String]

    var body: some View {
        Menu {
            ForEach(SystemAction.allCases, id: \.self) { s in
                Button { action = .system(s) } label: { Label(s.title, systemImage: s.symbol) }
            }
            Divider()
            Menu {
                if shortcuts.isEmpty { Text("No shortcuts found") }
                ForEach(shortcuts, id: \.self) { name in
                    Button(name.trimmingCharacters(in: .whitespaces)) { action = .shortcut(name) }
                }
            } label: {
                Label("Run Shortcut", systemImage: "command")
            }
            Divider()
            Button { action = .none } label: { Label("No Action", systemImage: "circle.dashed") }
        } label: {
            Label(action.title, systemImage: action.symbol)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

extension Binding {
    /// Reads and writes a non-optional value as an optional; writing nil changes nothing.
    var optional: Binding<Value?> {
        Binding<Value?>(get: { wrappedValue }, set: { if let v = $0 { wrappedValue = v } })
    }
}

/// Preset swatches and, last, a rainbow one that opens the color panel for a custom color.
struct ColorSwatches: View {
    @Binding var selection: GlowColor?
    var allowNone = false

    var body: some View {
        HStack(spacing: 8) {
            if allowNone {
                Image(systemName: "nosign").foregroundStyle(.secondary).frame(width: 18, height: 18)
                    .ringed(selection == nil).help("None").onTapGesture { selection = nil }
            }
            ForEach(GlowColor.presets, id: \.self) { preset in
                Circle().fill(preset.swiftUIColor).frame(width: 18, height: 18)
                    .ringed(selection == preset).help(preset.title).onTapGesture { selection = preset }
            }
            rainbow
        }
    }

    private var isCustom: Bool {
        if case .custom? = selection { return true }
        return false
    }

    private var rainbow: some View {
        ZStack {
            if case .custom(let hex)? = selection {
                Circle().fill(GlowColor.custom(hex: hex).swiftUIColor)
            } else {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red], center: .center))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: isCustom ? 1 : 0))
        .ringed(isCustom).help("Custom color")
        .contentShape(Circle())
        .onTapGesture {
            ColorPanelBridge.shared.open(initial: selection?.swiftUIColor ?? .blue) { selection = .custom(hex: GlowColor.hex(of: $0)) }
        }
    }
}

private extension View {
    func ringed(_ on: Bool) -> some View {
        overlay(Circle().strokeBorder(.primary.opacity(on ? 0.9 : 0), lineWidth: 2).padding(-3))
    }
}

/// Opens the system color panel and reports each color picked. (A SwiftUI `ColorPicker` can't be hidden behind a
/// swatch without stealing its neighbors' clicks.)
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((Color) -> Void)?

    func open(initial: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(nil)
        panel.color = NSColor(initial)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}
