import Foundation

public enum Smoothness: String, Codable, CaseIterable, Identifiable {
    case off, regular, high
    public var id: String { rawValue }
    public var title: String { ["off": "Off", "regular": "Regular", "high": "High"][rawValue]! }
    /// Time constant of the exponential ease-out, in seconds. 0 = instant.
    public var timeConstant: Double {
        switch self {
        case .off: return 0
        case .regular: return 0.085
        case .high: return 0.16
        }
    }
}

public enum ScrollSpeed: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var pixelsPerTick: Double {
        switch self {
        case .low: return 36
        case .medium: return 64
        case .high: return 100
        }
    }
}

public enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case click, doubleClick, hold
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .click: return "Click"
        case .doubleClick: return "Double Click"
        case .hold: return "Hold"
        }
    }
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case back, forward, missionControl, appWindows, showDesktop
    case spaceLeft, spaceRight, middleClick, lookUp, keyboardShortcut
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App Windows"
        case .showDesktop: return "Show Desktop"
        case .spaceLeft: return "Move Left a Space"
        case .spaceRight: return "Move Right a Space"
        case .middleClick: return "Middle Click"
        case .lookUp: return "Look Up"
        case .keyboardShortcut: return "Keyboard Shortcut…"
        }
    }
    public var symbol: String {
        switch self {
        case .back: return "chevron.backward"
        case .forward: return "chevron.forward"
        case .missionControl: return "rectangle.3.group"
        case .appWindows: return "macwindow.on.rectangle"
        case .showDesktop: return "menubar.dock.rectangle"
        case .spaceLeft: return "arrow.left.square"
        case .spaceRight: return "arrow.right.square"
        case .middleClick: return "computermouse"
        case .lookUp: return "character.book.closed"
        case .keyboardShortcut: return "keyboard"
        }
    }
}

public struct Shortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    /// Raw CGEventFlags device-independent modifier mask.
    public var modifiers: UInt64
    public var display: String
    public init(keyCode: UInt16, modifiers: UInt64, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }
}

public struct ButtonMapping: Codable, Equatable, Identifiable {
    public var id = UUID()
    /// Human button number: 3 = middle, 4 = back side button, 5 = forward side button, ...
    public var button: Int
    public var trigger: TriggerKind
    public var action: ActionKind
    public var shortcut: Shortcut?
    public init(button: Int, trigger: TriggerKind, action: ActionKind, shortcut: Shortcut? = nil) {
        self.button = button
        self.trigger = trigger
        self.action = action
        self.shortcut = shortcut
    }
}

public struct GlideSettings: Codable, Equatable {
    public var enabled = true
    public var showMenuBarIcon = true

    // Scrolling
    public var scrollEnabled = true
    public var smoothness: Smoothness = .regular
    public var speed: ScrollSpeed = .medium
    public var acceleration = true
    public var reverseDirection = false
    public var trackpadLike = true
    public var horizontalModifier = true // ⇧
    public var preciseModifier = true // ⌥
    public var swiftModifier = true // ⌃
    public var zoomModifier = true // ⌘

    // Buttons
    public var buttonsEnabled = true
    public var mappings: [ButtonMapping] = GlideSettings.defaultMappings

    public init() {}

    public static let defaultMappings: [ButtonMapping] = [
        ButtonMapping(button: 3, trigger: .hold, action: .missionControl),
        ButtonMapping(button: 4, trigger: .click, action: .back),
        ButtonMapping(button: 4, trigger: .hold, action: .showDesktop),
        ButtonMapping(button: 5, trigger: .click, action: .forward),
        ButtonMapping(button: 5, trigger: .hold, action: .appWindows),
    ]

    /// Tolerant decoding: unknown/missing keys fall back to defaults so old configs keep working.
    public init(from decoder: Decoder) throws {
        let d = GlideSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        showMenuBarIcon = (try? c.decode(Bool.self, forKey: .showMenuBarIcon)) ?? d.showMenuBarIcon
        scrollEnabled = (try? c.decode(Bool.self, forKey: .scrollEnabled)) ?? d.scrollEnabled
        smoothness = (try? c.decode(Smoothness.self, forKey: .smoothness)) ?? d.smoothness
        speed = (try? c.decode(ScrollSpeed.self, forKey: .speed)) ?? d.speed
        acceleration = (try? c.decode(Bool.self, forKey: .acceleration)) ?? d.acceleration
        reverseDirection = (try? c.decode(Bool.self, forKey: .reverseDirection)) ?? d.reverseDirection
        trackpadLike = (try? c.decode(Bool.self, forKey: .trackpadLike)) ?? d.trackpadLike
        horizontalModifier = (try? c.decode(Bool.self, forKey: .horizontalModifier)) ?? d.horizontalModifier
        preciseModifier = (try? c.decode(Bool.self, forKey: .preciseModifier)) ?? d.preciseModifier
        swiftModifier = (try? c.decode(Bool.self, forKey: .swiftModifier)) ?? d.swiftModifier
        zoomModifier = (try? c.decode(Bool.self, forKey: .zoomModifier)) ?? d.zoomModifier
        buttonsEnabled = (try? c.decode(Bool.self, forKey: .buttonsEnabled)) ?? d.buttonsEnabled
        mappings = (try? c.decode([ButtonMapping].self, forKey: .mappings)) ?? d.mappings
    }

    /// Which triggers have an action for a given button.
    public func clickConfig(for button: Int) -> ClickConfig? {
        let m = mappings.filter { $0.button == button }
        guard !m.isEmpty else { return nil }
        return ClickConfig(
            hasClick: m.contains { $0.trigger == .click },
            hasDouble: m.contains { $0.trigger == .doubleClick },
            hasHold: m.contains { $0.trigger == .hold }
        )
    }

    public func mapping(button: Int, trigger: TriggerKind) -> ButtonMapping? {
        mappings.first { $0.button == button && $0.trigger == trigger }
    }
}
