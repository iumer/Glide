import AppKit
import GlideCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, buttons, scroll, about
    var id: String { rawValue }
}

struct SettingsView: View {
    @State var tab: SettingsTab

    init(initialTab: SettingsTab) { _tab = State(initialValue: initialTab) }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            ButtonsTab().tabItem { Label("Buttons", systemImage: "computermouse") }.tag(SettingsTab.buttons)
            ScrollTab().tabItem { Label("Scrolling", systemImage: "scroll") }.tag(SettingsTab.scroll)
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .padding(.top, 8)
        .frame(width: 640, height: 660)
        .onReceive(NotificationCenter.default.publisher(for: .glideSelectTab)) { note in
            if let t = note.object as? SettingsTab { tab = t }
        }
    }
}

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var engine: GlideEngine

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    AppBadge(size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Glide").font(.title2.weight(.semibold))
                        Text(statusText).foregroundStyle(statusColor)
                    }
                    Spacer()
                    Toggle("", isOn: $store.settings.enabled).toggleStyle(.switch).labelsHidden()
                }
                .padding(.vertical, 4)
            }

            if !engine.isTrusted {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility access is required", systemImage: "hand.raised.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Glide reads your mouse's scroll wheel and buttons through macOS Accessibility. Turn on **Glide** in System Settings › Privacy & Security › Accessibility. Glide starts working the moment access is granted.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }

            if engine.otherMouseAppRunning {
                Section {
                    Label {
                        Text("Another mouse utility (e.g. Mac Mouse Fix) is running. Use one at a time — two apps smoothing the same scroll wheel will fight each other.")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                }
            }

            Section("Features") {
                Toggle("Smooth scrolling", isOn: $store.settings.scrollEnabled)
                Toggle("Button actions", isOn: $store.settings.buttonsEnabled)
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                Toggle("Show in menu bar", isOn: $store.settings.showMenuBarIcon)
                if !store.settings.showMenuBarIcon {
                    Text("Glide keeps running. Open it again from Applications to see these settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    var statusText: String {
        if !engine.isTrusted { return "Waiting for Accessibility access" }
        if !store.settings.enabled { return "Paused" }
        return engine.isRunning ? "Active — your mouse is enhanced" : "Starting…"
    }

    var statusColor: Color {
        if !engine.isTrusted { return .orange }
        return store.settings.enabled && engine.isRunning ? .green : .secondary
    }
}

// MARK: - Scrolling

struct ScrollTab: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Smooth scrolling", isOn: $store.settings.scrollEnabled)
                Picker("Smoothness", selection: $store.settings.smoothness) {
                    ForEach(Smoothness.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Speed", selection: $store.settings.speed) {
                    ForEach(ScrollSpeed.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $store.settings.acceleration) {
                    Text("Acceleration")
                    Text("Scroll faster the quicker you flick the wheel").font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $store.settings.trackpadLike) {
                    Text("Trackpad-like feel")
                    Text("Apps treat the wheel like a trackpad gesture (rubber-band edges)").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Reverse direction", isOn: $store.settings.reverseDirection)
            }
            .disabled(!store.settings.scrollEnabled)

            Section("Hold a key while scrolling") {
                ModifierRow(key: "⇧", title: "Scroll horizontally", detail: "Move sideways through timelines and wide pages", isOn: $store.settings.horizontalModifier)
                ModifierRow(key: "⌥", title: "Scroll precisely", detail: "Tiny steps for sliders and fine positioning", isOn: $store.settings.preciseModifier)
                ModifierRow(key: "⌃", title: "Scroll swiftly", detail: "Cover long documents with little effort", isOn: $store.settings.swiftModifier)
                ModifierRow(key: "⌘", title: "Zoom in or out", detail: "Works in Safari, Chrome, Preview and more", isOn: $store.settings.zoomModifier)
            }
            .disabled(!store.settings.scrollEnabled)
        }
        .formStyle(.grouped)
    }
}

struct ModifierRow: View {
    let key: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Text(key)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppBadge(size: 96)
            Text("Glide").font(.largeTitle.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Smooth scrolling and programmable buttons for any mouse.")
                .multilineTextAlignment(.center)
            Text("An independent app. Its design was informed by studying how Mac Mouse Fix behaves; no code from it is used.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct AppBadge: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.42, blue: 1.0), Color(red: 0.55, green: 0.27, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "computermouse.fill")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: size * 0.05, y: size * 0.03)
    }
}
