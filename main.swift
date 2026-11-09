// HotCorners: a tiny menu bar app that replaces the macOS hot corners.
// It polls the mouse position, and when the pointer rests in a screen corner it runs the action assigned to it
// (optionally a different one while ⌘, ⌥, ⌃ or ⇧ is held). No Accessibility permission needed.

import Cocoa
import Combine
import IOKit.pwr_mgt
import ServiceManagement
import SwiftUI

// MARK: - Model

enum Corner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var defaultAction: CornerAction {
        switch self {
        case .topLeft: return .system(.missionControl)
        case .topRight: return .system(.applicationWindows)
        case .bottomLeft: return .system(.desktop)
        case .bottomRight: return .system(.displaySleep)
        }
    }
}

/// Which key is held while the pointer reaches the corner.
enum Modifier: String, CaseIterable {
    case plain, command, option, control, shift

    var title: String { self == .plain ? "Corner Only" : rawValue.capitalized }

    var symbol: String {
        switch self {
        case .plain: return "cursorarrow"
        case .command: return "command"
        case .option: return "option"
        case .control: return "control"
        case .shift: return "shift"
        }
    }

    var glyph: String {
        switch self {
        case .plain: return ""
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    /// The modifier held right now (⌘ wins over ⌥, ⌃, ⇧).
    static var held: Modifier {
        let f = NSEvent.modifierFlags
        if f.contains(.command) { return .command }
        if f.contains(.option) { return .option }
        if f.contains(.control) { return .control }
        if f.contains(.shift) { return .shift }
        return .plain
    }
}

enum SystemAction: String, CaseIterable {
    case missionControl, applicationWindows, desktop, apps, startScreenSaver, disableScreenSaver, displaySleep, lockScreen

    var title: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .applicationWindows: return "Application Windows"
        case .desktop: return "Desktop"
        case .apps: return "Apps"
        case .startScreenSaver: return "Start Screen Saver"
        case .disableScreenSaver: return "Disable Screen Saver"
        case .displaySleep: return "Put Display to Sleep"
        case .lockScreen: return "Lock Screen"
        }
    }

    var symbol: String {
        switch self {
        case .missionControl: return "rectangle.3.group"
        case .applicationWindows: return "macwindow.on.rectangle"
        case .desktop: return "menubar.dock.rectangle"
        case .apps: return "square.grid.3x3"
        case .startScreenSaver: return "sparkles.tv"
        case .disableScreenSaver: return "tv.slash"
        case .displaySleep: return "moon.zzz"
        case .lockScreen: return "lock"
        }
    }

    /// Lasts while the pointer stays in the corner.
    var isHold: Bool { self == .disableScreenSaver }
}

enum CornerAction: Hashable {
    case none
    case system(SystemAction)
    case shortcut(String)

    var title: String {
        switch self {
        case .none: return "No Action"
        case .system(let s): return s.title
        case .shortcut(let n): return n.trimmingCharacters(in: .whitespaces)
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .system(let s): return s.symbol
        case .shortcut: return "command"
        }
    }

    var storedText: String {
        switch self {
        case .none: return "none"
        case .system(let s): return "system.\(s.rawValue)"
        case .shortcut(let n): return "shortcut:\(n)"
        }
    }

    init(storedText t: String) {
        if t.hasPrefix("system."), let s = SystemAction(rawValue: String(t.dropFirst(7))) {
            self = .system(s)
        } else if t.hasPrefix("shortcut:") {
            self = .shortcut(String(t.dropFirst(9)))
        } else {
            self = .none
        }
    }
}

let delayChoices: [(label: String, value: Double)] = [
    ("Instant", 0), ("0.15 s", 0.15), ("0.3 s", 0.3), ("0.5 s", 0.5), ("1 s", 1), ("2 s", 2),
]

// MARK: - Actions

private typealias CoreDockSendNotificationFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
private typealias LockScreenFn = @convention(c) () -> Int32

/// The Dock's own entry point for Mission Control, App Exposé and Show Desktop (private API, resolved at runtime).
private let coreDockSendNotification: CoreDockSendNotificationFn? = {
    let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    guard let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
    return unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
}()

private let lockScreenCall: LockScreenFn? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
        let sym = dlsym(handle, "SACLockScreenImmediate")
    else { return nil }
    return unsafeBitCast(sym, to: LockScreenFn.self)
}()

private func sendDock(_ name: String) -> Bool {
    guard let send = coreDockSendNotification else { return false }
    send(name as CFString, nil)
    return true
}

private func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try? p.run()
}

private func openApp(_ path: String) {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
}

private var holdAssertion: IOPMAssertionID = 0

private func beginHold() {
    endHold()
    var id: IOPMAssertionID = 0
    let r = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Hot Corners: screen saver disabled" as CFString, &id)
    if r == kIOReturnSuccess { holdAssertion = id }
}

func endHold() {
    guard holdAssertion != 0 else { return }
    IOPMAssertionRelease(holdAssertion)
    holdAssertion = 0
}

func perform(_ action: CornerAction) {
    switch action {
    case .none:
        break
    case .shortcut(let name):
        if !name.isEmpty { run("/usr/bin/shortcuts", ["run", name]) }
    case .system(let s):
        switch s {
        case .missionControl:
            if !sendDock("com.apple.expose.awake") { run("/usr/bin/open", ["-a", "Mission Control"]) }
        case .applicationWindows:
            if !sendDock("com.apple.expose.front.awake") { run("/usr/bin/open", ["-a", "Mission Control", "--args", "2"]) }
        case .desktop:
            _ = sendDock("com.apple.showdesktop.awake")
        case .apps:
            if FileManager.default.fileExists(atPath: "/System/Applications/Apps.app") {
                openApp("/System/Applications/Apps.app")
            } else {
                _ = sendDock("com.apple.launchpad.toggle")
            }
        case .startScreenSaver:
            openApp("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .disableScreenSaver:
            beginHold()
        case .displaySleep:
            run("/usr/bin/pmset", ["displaysleepnow"])
        case .lockScreen:
            if let lock = lockScreenCall { _ = lock() } else { run("/usr/bin/pmset", ["displaysleepnow"]) }
        }
    }
}

/// Names of the user's shortcuts, exactly as the CLI prints them (some end in spaces, which `shortcuts run` needs).
func listShortcuts() -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    p.arguments = ["list"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

// MARK: - Settings

final class Settings: ObservableObject {
    private let d = UserDefaults.standard

    var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { objectWillChange.send(); d.set(newValue, forKey: "enabled") }
    }

    var glow: GlowConfig {
        get {
            var g = GlowConfig()
            g.enabled = d.object(forKey: "glow.enabled") as? Bool ?? true
            g.color = GlowColor(storedText: d.string(forKey: "glow.color") ?? "accent")
            g.secondary = d.string(forKey: "glow.color2").flatMap { $0 == "none" ? nil : GlowColor(storedText: $0) }
            g.balance = d.object(forKey: "glow.balance") as? Double ?? g.balance
            g.whiteCore = d.object(forKey: "glow.whiteCore") as? Bool ?? g.whiteCore
            g.style = d.string(forKey: "glow.style").flatMap(GlowStyle.init(rawValue:)) ?? .glow
            g.size = d.string(forKey: "glow.size").flatMap(GlowSize.init(rawValue:)) ?? .medium
            g.duration = d.object(forKey: "glow.duration") as? Double ?? g.duration
            g.opacity = d.object(forKey: "glow.opacity") as? Double ?? g.opacity
            return g
        }
        set {
            objectWillChange.send()
            d.set(newValue.enabled, forKey: "glow.enabled")
            d.set(newValue.color.storedText, forKey: "glow.color")
            d.set(newValue.secondary?.storedText ?? "none", forKey: "glow.color2")
            d.set(newValue.balance, forKey: "glow.balance")
            d.set(newValue.whiteCore, forKey: "glow.whiteCore")
            d.set(newValue.style.rawValue, forKey: "glow.style")
            d.set(newValue.size.rawValue, forKey: "glow.size")
            d.set(newValue.duration, forKey: "glow.duration")
            d.set(newValue.opacity, forKey: "glow.opacity")
        }
    }

    func action(for corner: Corner, _ mod: Modifier) -> CornerAction {
        if let text = d.string(forKey: "corner.\(corner.rawValue).\(mod.rawValue)") {
            return CornerAction(storedText: text)
        }
        guard mod == .plain else { return .none }
        return legacyAction(for: corner) ?? corner.defaultAction
    }

    func setAction(_ action: CornerAction, for corner: Corner, _ mod: Modifier) {
        objectWillChange.send()
        d.set(action.storedText, forKey: "corner.\(corner.rawValue).\(mod.rawValue)")
    }

    /// Seconds the pointer must rest in this corner before its action fires.
    func delay(for corner: Corner) -> Double {
        d.object(forKey: "corner.\(corner.rawValue).delay") as? Double ?? d.object(forKey: "delay") as? Double ?? 0.15
    }

    func setDelay(_ seconds: Double, for corner: Corner) {
        objectWillChange.send()
        d.set(seconds, forKey: "corner.\(corner.rawValue).delay")
    }

    /// Settings of the first version: one action per corner under `corner.<corner>`.
    private func legacyAction(for corner: Corner) -> CornerAction? {
        switch d.string(forKey: "corner.\(corner.rawValue)") {
        case "none": return CornerAction.none
        case "missionControl": return .system(.missionControl)
        case "appWindows": return .system(.applicationWindows)
        case "showDesktop": return .system(.desktop)
        case "displaySleep": return .system(.displaySleep)
        case "screenSaver": return .system(.startScreenSaver)
        case "shortcut": return d.string(forKey: "corner.\(corner.rawValue).shortcut").map { .shortcut($0) }
        default: return nil
        }
    }
}

// MARK: - Corner tracking

@MainActor
final class CornerWatcher {
    private let settings: Settings
    private var timer: Timer?
    private var current: Corner?
    private var enteredAt = Date.distantPast
    private var fired = false
    /// the drag pasteboard's change count while no mouse button was down, to tell a file drag from a window drag
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    /// whether the last tick was a drag and drop in progress
    private var wasDragAndDrop = false

    /// Distance from the corner (in points) that still counts as "in the corner".
    private let tolerance: CGFloat = 3

    nonisolated init(settings: Settings) { self.settings = settings }

    func start() {
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard settings.enabled else { reset(); return }
        // Dragging a window into a corner fires nothing (macOS tiles it there). Dragging a file, an image or text does, after the
        // corner's own delay like a plain visit: a drag and drop writes the drag pasteboard after the button went down, a window
        // drag doesn't. The baseline is the count seen while no button was down.
        let down = NSEvent.pressedMouseButtons != 0
        let count = NSPasteboard(name: .drag).changeCount
        if !down { dragBaseline = count }
        let dragAndDrop = down && count != dragBaseline
        guard !down || dragAndDrop else { wasDragAndDrop = false; reset(); return }
        // Dropped in the corner: this visit is over; it fires again only after the pointer leaves and comes back.
        if wasDragAndDrop && !down { fired = true }
        wasDragAndDrop = dragAndDrop

        let hit = cornerUnderMouse()
        let corner = hit?.0
        if corner != current {
            endHold()
            current = corner
            enteredAt = Date()
            fired = false
        }
        guard let corner, !fired, Date().timeIntervalSince(enteredAt) >= settings.delay(for: corner) else { return }
        fired = true
        let action = settings.action(for: corner, Modifier.held)
        guard action != .none else { return }
        perform(action)
        if settings.glow.enabled, let frame = hit?.1 {
            GlowPanel.show(at: corner, screen: frame, glow: settings.glow)
        }
    }

    private func reset() {
        endHold()
        current = nil
        fired = false
    }

    private func cornerUnderMouse() -> (Corner, CGRect)? {
        let p = NSEvent.mouseLocation  // global, bottom-left origin, same space as NSScreen.frame
        for screen in NSScreen.screens {
            let f = screen.frame
            guard f.insetBy(dx: -1, dy: -1).contains(p) else { continue }
            let left = p.x <= f.minX + tolerance
            let right = p.x >= f.maxX - 1 - tolerance
            let bottom = p.y <= f.minY + tolerance
            let top = p.y >= f.maxY - 1 - tolerance
            switch (left, right, top, bottom) {
            case (true, _, true, _): return (.topLeft, f)
            case (_, true, true, _): return (.topRight, f)
            case (true, _, _, true): return (.bottomLeft, f)
            case (_, true, _, true): return (.bottomRight, f)
            default: return nil
            }
        }
        return nil
    }
}

// MARK: - Menu bar UI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var watcher = CornerWatcher(settings: settings)
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Hot Corners")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        settings.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateIcon() } }.store(in: &bag)
        watcher.start()
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.enabled ? .on : .off
        toggle.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(toggle)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        prefs.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefs)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Hot Corners", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Hot Corners", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    @objc private func openSettings() {
        if window == nil {
            let view = SettingsView(settings: settings, shortcuts: listShortcuts()) { [weak self] corner in
                guard let self, let f = NSScreen.main?.frame else { return }
                GlowPanel.show(at: corner, screen: f, glow: self.settings.glow)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Hot Corners"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The standard About panel; it takes the icon, name, version and copyright from the bundle.
    @objc private func showAbout() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let credits = NSAttributedString(
            string: "Hot corners for Macs where the built-in ones are blocked.\nFree software under the GPL-3.0 license.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style,
            ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
    }

    private func updateIcon() {
        statusItem.button?.appearsDisabled = !settings.enabled
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
