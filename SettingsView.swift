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
    @State private var hovered: Corner?

    var body: some View {
        // Two columns: general switches and the live preview stay put on the left, the settings scroll on the right.
        // With the app switched off only the general switches are shown.
        HStack(spacing: 0) {
            leftColumn
            if settings.enabled {
                Divider()
                settingsForm.frame(width: Self.rightWidth)
            }
        }
        .frame(
            width: settings.enabled ? Self.leftWidth + 1 + Self.rightWidth : Self.leftWidth,
            height: settings.enabled ? 600 : 190)
    }

    private static let leftWidth: CGFloat = 420
    private static let rightWidth: CGFloat = 480

    // MARK: Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            generalCard
            if settings.enabled {
                mockup
                HStack {
                    Spacer()
                    Button("Replay") { previewToken += 1 }
                    Button("Test on Screen") { testOnScreen(selected) }
                }
                .disabled(!settings.glow.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: Self.leftWidth, alignment: .top)
    }

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General").font(.headline)
            VStack(spacing: 0) {
                switchRow("Enabled", isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 }))
                Divider().padding(.horizontal, 12)
                switchRow("Open at Login", isOn: Binding(get: { loginEnabled }, set: setLogin))
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    // MARK: Right column

    private var settingsForm: some View {
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
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Mockup

    /// A 16:9 "screen" with a card in each corner. The clear base view sets the 16:9 shape; the screen is drawn over it.
    private var mockup: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { screen }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }

    private var screen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.30, blue: 0.82), Color(red: 0.26, green: 0.12, blue: 0.46), Color(red: 0.56, green: 0.20, blue: 0.46)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            if settings.glow.enabled {
                GlowView(corner: selected, glow: settings.glow, side: 120)
                    .id(previewToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(of: selected))
            }
            Text("Click a corner to edit it")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            VStack {
                menuBar
                Spacer()
            }
            VStack {
                HStack(alignment: .top) { card(.topLeft); Spacer(minLength: 8); card(.topRight) }
                Spacer()
                HStack(alignment: .bottom) { card(.bottomLeft); Spacer(minLength: 8); card(.bottomRight) }
            }
            .padding(.horizontal, 12).padding(.top, 32).padding(.bottom, 12)
        }
    }

    private var menuBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.logo").font(.caption)
            ForEach([34, 22, 28], id: \.self) { Capsule().fill(.white.opacity(0.7)).frame(width: CGFloat($0), height: 5) }
            Spacer()
            ForEach([12, 12, 34], id: \.self) { Capsule().fill(.white.opacity(0.7)).frame(width: CGFloat($0), height: 5) }
        }
        .padding(.horizontal, 12).frame(height: 22).background(.black.opacity(0.18))
        .foregroundStyle(.white)
    }

    private func card(_ corner: Corner) -> some View {
        let plain = settings.action(for: corner, .plain)
        let delay = settings.delay(for: corner)
        let extras = Modifier.allCases.filter { $0 != .plain && settings.action(for: corner, $0) != .none }
        let isRight = !corner.isLeft
        return VStack(alignment: isRight ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: plain.symbol)
                Text(plain.title).fontWeight(.semibold).lineLimit(1)
            }
            HStack(spacing: 3) {
                Image(systemName: "clock")
                Text(delay == 0 ? "Instant" : String(format: "%g s", delay))
            }
            .font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.65))
            // the preview is small, so the modifier actions show as glyphs only; the details are in the list on the right
            if !extras.isEmpty {
                HStack(spacing: 4) {
                    ForEach(extras, id: \.self) { mod in
                        Text(mod.glyph).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.white.opacity(0.16), in: Capsule())
                            .help("\(mod.title): \(settings.action(for: corner, mod).title)")
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minWidth: 130, alignment: isRight ? .trailing : .leading)
        .background(.black.opacity(hovered == corner ? 0.42 : 0.30), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: selected == corner ? 2.5 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { inside in
            if inside { hovered = corner } else if hovered == corner { hovered = nil }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onTapGesture { selected = corner; previewToken += 1 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(corner.title) corner")
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
