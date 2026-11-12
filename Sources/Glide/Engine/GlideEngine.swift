import AppKit
import ApplicationServices
import Combine
import GlideCore

/// Owns the event tap and routes events to the scroll and button controllers.
final class GlideEngine: ObservableObject {
    static let shared = GlideEngine()

    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var isRunning = false
    @Published private(set) var otherMouseAppRunning = false

    let scroll = ScrollController()
    let buttons = ButtonController()
    private var tap: EventTap?
    private var pollTimer: Timer?

    private static let conflictingBundleIDs = [
        "com.nuebling.mac-mouse-fix.helper",
        "com.caldis.Mos",
        "com.pilotmoon.scroll-reverser",
    ]

    func bootstrap(promptForAccess: Bool) {
        if !AXIsProcessTrusted() && promptForAccess {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted && tap == nil { start() }
        if !trusted && tap != nil { stop() }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let conflict = Self.conflictingBundleIDs.contains { running.contains($0) }
        if conflict != otherMouseAppRunning { otherMouseAppRunning = conflict }
        let alive = tap?.isRunning ?? false
        if alive != isRunning { isRunning = alive }
    }

    private func start() {
        let mask = CGEventType.scrollWheel.maskBit | CGEventType.otherMouseDown.maskBit |
            CGEventType.otherMouseUp.maskBit | CGEventType.otherMouseDragged.maskBit
        let t = EventTap(mask: mask) { [weak self] type, event in
            self?.route(type, event) ?? Unmanaged.passUnretained(event)
        }
        if t.start() {
            tap = t
            isRunning = true
        }
    }

    private func stop() {
        tap?.stop()
        tap = nil
        isRunning = false
    }

    /// Event-tap thread.
    private func route(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == glideEventMarker {
            return Unmanaged.passUnretained(event)
        }
        let s = SettingsStore.current
        switch type {
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            // Button capture must work even when Glide is paused.
            return buttons.handle(type, event, settings: s.enabled ? s : s.with { $0.buttonsEnabled = false })
        case .scrollWheel:
            return s.enabled ? scroll.handle(event, settings: s) : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

extension GlideSettings {
    func with(_ change: (inout GlideSettings) -> Void) -> GlideSettings {
        var copy = self
        change(&copy)
        return copy
    }
}
