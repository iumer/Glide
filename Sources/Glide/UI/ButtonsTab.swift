import AppKit
import GlideCore
import SwiftUI

struct ButtonsTab: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var engine: GlideEngine
    @State private var capturing = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Button actions", isOn: $store.settings.buttonsEnabled)
                } footer: {
                    Text("Left and right click are never changed. Buttons without an action keep their normal behaviour.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Actions") {
                    if store.settings.mappings.isEmpty {
                        Text("No actions yet — press **Add Action** and then a mouse button.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($store.settings.mappings.sorted { $0.wrappedValue.button < $1.wrappedValue.button }) { $mapping in
                        MappingRow(mapping: $mapping) {
                            store.settings.mappings.removeAll { $0.id == mapping.id }
                        }
                    }
                }
                .disabled(!store.settings.buttonsEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    capturing = true
                    engine.buttons.captureNextButton { button in
                        capturing = false
                        addMapping(for: button)
                    }
                } label: {
                    Label(capturing ? "Press a mouse button…" : "Add Action", systemImage: "plus")
                }
                .disabled(capturing || !engine.isTrusted)
                if capturing {
                    Button("Cancel") {
                        engine.buttons.captureNextButton(nil)
                        capturing = false
                    }
                }
                Spacer()
                Button("Restore Defaults") { store.resetButtons() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func addMapping(for button: Int) {
        let used = Set(store.settings.mappings.filter { $0.button == button }.map(\.trigger))
        let trigger = TriggerKind.allCases.first { !used.contains($0) } ?? .click
        let action: ActionKind = button == 4 ? .back : button == 5 ? .forward : .missionControl
        store.settings.mappings.append(ButtonMapping(button: button, trigger: trigger, action: action))
    }
}

struct MappingRow: View {
    @Binding var mapping: ButtonMapping
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mapping.action.symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Picker("", selection: $mapping.button) {
                ForEach(3...12, id: \.self) { n in Text(buttonName(n)).tag(n) }
            }
            .labelsHidden()
            .frame(width: 128)
            Picker("", selection: $mapping.trigger) {
                ForEach(TriggerKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 118)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("", selection: $mapping.action) {
                ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            if mapping.action == .keyboardShortcut {
                ShortcutRecorder(shortcut: $mapping.shortcut)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Remove this action")
        }
    }

    private func buttonName(_ n: Int) -> String {
        switch n {
        case 3: return "Middle Button"
        case 4: return "Button 4 (Back)"
        case 5: return "Button 5 (Fwd)"
        default: return "Button \(n)"
        }
    }
}

/// Click, then press a key combination.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : (shortcut?.display ?? "Record")) {
            recording ? stop() : start()
        }
        .frame(minWidth: 88)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc cancels
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: UInt64(mods.rawValue),
                                display: symbols(mods) + keyName(event.keyCode, fallback: key))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func symbols(_ m: NSEvent.ModifierFlags) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") +
            (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    private func keyName(_ code: UInt16, fallback: String) -> String {
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 123: "←", 124: "→",
                                       125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
                                       96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
                                       103: "F11", 111: "F12"]
        return names[code] ?? fallback
    }
}
