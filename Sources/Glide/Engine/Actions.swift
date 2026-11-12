import AppKit
import CoreGraphics
import GlideCore

/// Everything Glide can *do* in response to a button.
enum Actions {
    private static let source = CGEventSource(stateID: .hidSystemState)

    static func perform(_ mapping: ButtonMapping) {
        switch mapping.action {
        case .back: postKey(33, flags: .maskCommand) // ⌘[
        case .forward: postKey(30, flags: .maskCommand) // ⌘]
        case .missionControl: dock("com.apple.expose.awake", fallbackApp: "Mission Control")
        case .appWindows: dock("com.apple.expose.front.awake", fallbackKey: (125, .maskControl)) // ⌃↓
        case .showDesktop: dock("com.apple.showdesktop.awake", fallbackKey: (103, [])) // F11
        case .spaceLeft: postKey(123, flags: .maskControl) // ⌃←
        case .spaceRight: postKey(124, flags: .maskControl) // ⌃→
        case .middleClick: postClick(button: 3)
        case .lookUp: postKey(2, flags: [.maskCommand, .maskControl]) // ⌃⌘D
        case .keyboardShortcut:
            if let s = mapping.shortcut {
                postKey(CGKeyCode(s.keyCode), flags: CGEventFlags(rawValue: s.modifiers))
            }
        }
    }

    // MARK: Primitives

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        for e in [down, up] {
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: glideEventMarker)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Post a full click of a human-numbered button (3 = middle, 4, 5, …).
    static func postClick(button: Int, at location: CGPoint? = nil) {
        postButton(button, down: true, at: location)
        postButton(button, down: false, at: location)
    }

    static func postButton(_ button: Int, down: Bool, at location: CGPoint? = nil) {
        let raw = UInt32(max(button - 1, 2))
        guard let e = CGEvent(mouseEventSource: source,
                              mouseType: down ? .otherMouseDown : .otherMouseUp,
                              mouseCursorPosition: location ?? cursorLocation,
                              mouseButton: CGMouseButton(rawValue: raw) ?? .center) else { return }
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(raw))
        e.setIntegerValueField(.eventSourceUserData, value: glideEventMarker)
        e.post(tap: .cgSessionEventTap)
    }

    static func zoom(in zoomIn: Bool) {
        postKey(zoomIn ? 24 : 27, flags: .maskCommand) // ⌘= / ⌘-
    }

    // MARK: Dock / Mission Control

    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void
    private static let coreDock: CoreDockSendNotification? = {
        let handle = dlopen(nil, RTLD_NOW)
        guard let sym = dlsym(handle, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotification.self)
    }()

    private static func dock(_ note: String, fallbackApp: String? = nil, fallbackKey: (CGKeyCode, CGEventFlags)? = nil) {
        if let send = coreDock {
            send(note as CFString, 0)
        } else if let app = fallbackApp {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/\(app).app"))
        } else if let (k, f) = fallbackKey {
            postKey(k, flags: f)
        }
    }
}
