import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--live-test") {
    // Hidden test mode: exercise the *running* Glide instance end-to-end, then exit.
    exit(runLiveTest(Set(CommandLine.arguments[(i + 1)...])))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
