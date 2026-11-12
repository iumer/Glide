import Foundation
import GlideCore

var failures = 0
func check(_ cond: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if cond { print("PASS  \(name)") } else { failures += 1; print("FAIL  \(name) \(detail())") }
}

// MARK: ScrollAnimator

func run(_ a: ScrollAnimator, tau: Double, fps: Double = 120, maxFrames: Int = 2000) -> (total: (Int, Int), frames: Int) {
    var tx = 0, ty = 0, n = 0
    while !a.isIdle && n < maxFrames {
        let (x, y) = a.step(dt: 1 / fps, timeConstant: tau)
        tx += x; ty += y; n += 1
    }
    return ((tx, ty), n)
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 64, acceleration: 0, timeConstant: 0.085)
    a.addTick(dx: 0, dy: 1, at: 0, params: p)
    let r = run(a, tau: p.timeConstant)
    check(r.total == (0, 64), "single tick delivers exactly 64px", "\(r.total)")
    check(r.frames > 5 && r.frames < 200, "single tick animates over several frames", "\(r.frames) frames")
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 64, acceleration: 0, timeConstant: 0)
    a.addTick(dx: 0, dy: -2, at: 0, params: p)
    let r = run(a, tau: 0)
    check(r.total == (0, -128) && r.frames == 1, "smoothness off delivers instantly", "\(r)")
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 50, acceleration: 0.2, timeConstant: 0.1)
    for i in 0..<6 { a.addTick(dx: 0, dy: 1, at: Double(i) * 0.03, params: p) }
    check(a.streak == 5, "fast consecutive ticks build a streak", "streak \(a.streak)")
    // 50 * (1 + 1 + 1.2 + 1.4 + 1.6 + 1.8 + 2.0)… = 50 * (1+1.2+1.4+1.6+1.8+2.0) = 450
    let r = run(a, tau: p.timeConstant)
    check(r.total.1 == 450, "acceleration total is 450px", "\(r.total)")
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 50, acceleration: 0.2, timeConstant: 0.1)
    a.addTick(dx: 0, dy: 1, at: 0, params: p)
    a.addTick(dx: 0, dy: 1, at: 0.05, params: p)
    a.addTick(dx: 0, dy: -1, at: 0.10, params: p)
    check(a.remainingY == -50 && a.streak == 0, "direction change cancels remaining and streak", "\(a.remainingY) \(a.streak)")
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 50, acceleration: 0.2, timeConstant: 0.1)
    a.addTick(dx: 0, dy: 1, at: 0, params: p)
    a.addTick(dx: 0, dy: 1, at: 0.05, params: p)
    a.addTick(dx: 0, dy: 1, at: 1.0, params: p)
    check(a.streak == 0, "pause resets streak")
}

do {
    let a = ScrollAnimator()
    let p = ScrollParams(pixelsPerTick: 37.3, acceleration: 0, timeConstant: 0.16)
    a.addTick(dx: 1, dy: 3, at: 0, params: p)
    let r = run(a, tau: 0.16)
    check(abs(r.total.0 - 37) <= 1 && abs(r.total.1 - 112) <= 1, "fractional speeds stay within 1px", "\(r.total)")
}

// MARK: ClickDetector

func cd(_ click: Bool, _ dbl: Bool, _ hold: Bool) -> ClickDetector {
    ClickDetector(config: ClickConfig(hasClick: click, hasDouble: dbl, hasHold: hold))
}

do {
    let d = cd(true, false, true)
    _ = d.down(at: 0); let out = d.up(at: 0.1)
    check(out == [.click], "quick press = click", "\(out)")
}
do {
    let d = cd(true, false, true)
    _ = d.down(at: 0)
    check(d.nextDeadline == 0.35, "hold deadline scheduled")
    let h = d.tick(at: 0.36); let u = d.up(at: 0.8)
    check(h == [.hold] && u.isEmpty, "long press = hold only", "\(h) \(u)")
}
do {
    let d = cd(true, true, false)
    _ = d.down(at: 0); let u1 = d.up(at: 0.05)
    _ = d.down(at: 0.15); let u2 = d.up(at: 0.2)
    check(u1.isEmpty && u2 == [.doubleClick], "two quick presses = double click", "\(u1) \(u2)")
}
do {
    let d = cd(true, true, false)
    _ = d.down(at: 0); _ = d.up(at: 0.05)
    check(d.tick(at: 0.2).isEmpty, "waits during double-click window")
    check(d.tick(at: 0.31) == [.click], "single click fires after window")
}
do {
    let d = cd(false, false, true)
    _ = d.down(at: 0); let out = d.up(at: 0.1)
    check(out == [.passthrough], "unmapped click passes through (middle click still works)", "\(out)")
}
do {
    let d = cd(true, false, false)
    _ = d.down(at: 0)
    check(d.nextDeadline == nil && d.tick(at: 5).isEmpty, "no hold mapping = no hold")
    check(d.up(at: 5) == [.click], "long press without hold mapping is a click")
}

// MARK: Settings round-trip

do {
    var s = GlideSettings()
    s.speed = .high
    s.mappings.append(ButtonMapping(button: 6, trigger: .doubleClick, action: .keyboardShortcut,
                                    shortcut: Shortcut(keyCode: 1, modifiers: 0x100000, display: "⌘S")))
    let data = try! JSONEncoder().encode(s)
    let back = try! JSONDecoder().decode(GlideSettings.self, from: data)
    check(back == s, "settings encode/decode round-trip")
    let partial = try! JSONDecoder().decode(GlideSettings.self, from: Data(#"{"speed":"low"}"#.utf8))
    check(partial.speed == .low && partial.mappings == GlideSettings.defaultMappings, "partial config falls back to defaults")
    check(s.clickConfig(for: 4) == ClickConfig(hasClick: true, hasDouble: false, hasHold: true), "click config for button 4")
    check(s.clickConfig(for: 9) == nil, "unmapped button has no config")
}

print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
