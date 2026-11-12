import Combine
import Foundation
import GlideCore
import ServiceManagement

/// Persists settings and gives the event threads a lock-protected snapshot.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "GlideSettings.v1"
    private static let lock = NSLock()
    private static var snapshot = GlideSettings()

    /// Thread-safe read for the event tap.
    static var current: GlideSettings { lock.withLock { snapshot } }

    @Published var settings: GlideSettings {
        didSet {
            guard settings != oldValue else { return }
            Self.lock.withLock { Self.snapshot = settings }
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        var loaded = GlideSettings()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(GlideSettings.self, from: data) {
            loaded = s
        }
        settings = loaded
        Self.lock.withLock { Self.snapshot = loaded }
    }

    func resetButtons() { settings.mappings = GlideSettings.defaultMappings }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Glide: launch-at-login change failed: \(error)")
            }
        }
    }
}
