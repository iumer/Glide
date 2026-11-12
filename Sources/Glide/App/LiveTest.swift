// Live end-to-end test of a running Glide.
// Injects synthetic "hardware" mouse events at the HID level, observes what Glide emits at the
// session level, and DROPS Glide's output (marker-tagged) so nothing actually happens on screen.
// Run via: open -n -W --stdout out.txt Glide.app --args --live-test [scenario...]
import AppKit
import CoreGraphics
import Foundation

// swiftlint:disable all

private let marker: Int64 = 0x474C_4944_45

private struct Seen {
    let t: Double
    let type: CGEventType
    let marked: Bool
    let continuous: Int64
    let lineDY: Int64, lineDX: Int64
    let pixDY: Double, pixDX: Double
    let phase: Int64
    let button: Int64
    let key: Int64
    let flags: CGEventFlags
}

private final class Observer {
    var log: [Seen] = []
    let lock = NSLock()
    var port: CFMachPort?

    func start() -> Bool {
        var mask: CGEventMask = 0
        for t: CGEventType in [.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .keyUp] {
            mask |= CGEventMask(1) << CGEventMask(t.rawValue)
        }
        let cb: CGEventTapCallBack = { _, type, e, refcon in
            let me = Unmanaged<Observer>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout { if let p = me.port { CGEvent.tapEnable(tap: p, enable: true) }; return Unmanaged.passUnretained(e) }
            let marked = e.getIntegerValueField(.eventSourceUserData) == marker
            let ours = e.getIntegerValueField(.eventSourceUserData) == 0x7E57
            let s = Seen(t: ProcessInfo.processInfo.systemUptime, type: type, marked: marked,
                         continuous: e.getIntegerValueField(.scrollWheelEventIsContinuous),
                         lineDY: e.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                         lineDX: e.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                         pixDY: e.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
                         pixDX: e.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                         phase: e.getIntegerValueField(.scrollWheelEventScrollPhase),
                         button: e.getIntegerValueField(.mouseEventButtonNumber),
                         key: e.getIntegerValueField(.keyboardEventKeycode),
                         flags: e.flags)
            if marked || ours {
                me.lock.withLock { me.log.append(s) }
                return nil // swallow: keep the test invisible to the user's apps
            }
            return Unmanaged.passUnretained(e)
        }
        guard let p = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: cb,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        port = p
        let src = CFMachPortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
        return true
    }

    func take() -> [Seen] { lock.withLock { let l = log; log = []; return l } }
}

private func describe(_ l: [Seen]) -> String {
    l.map { "\($0.marked ? "G" : "raw"):\($0.type.rawValue)/b\($0.button)/k\($0.key)/ph\($0.phase)/dy\($0.lineDY)" }.joined(separator: " ")
}

func runLiveTest(_ scenarios: Set<String>) -> Int32 {
    setvbuf(stdout, nil, _IOLBF, 0)
    let obs = Observer()
    guard obs.start() else { print("FAIL could not create observer tap (needs Accessibility for this process)"); return 2 }

    let src = CGEventSource(stateID: .privateState)
    func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    /// Raw (unmarked) events, as if from a real mouse. `tag` marks events Glide should NOT touch,
    /// so we can recognise them if they arrive unchanged.
    func tick(_ lines: Int32, horizontal: Bool = false, flags: CGEventFlags = []) {
        let e = CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 2,
                        wheel1: horizontal ? 0 : lines, wheel2: horizontal ? lines : 0, wheel3: 0)!
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: 0x7E57)
        e.post(tap: .cghidEventTap)
    }
    func button(_ n: Int64, down: Bool, at p: CGPoint) {
        let e = CGEvent(mouseEventSource: src, mouseType: down ? .otherMouseDown : .otherMouseUp,
                        mouseCursorPosition: p, mouseButton: CGMouseButton(rawValue: UInt32(n))!)!
        e.setIntegerValueField(.mouseEventButtonNumber, value: n)
        e.setIntegerValueField(.eventSourceUserData, value: 0x7E57)
        e.post(tap: .cghidEventTap)
    }
    func drag(_ n: Int64, to p: CGPoint) {
        let e = CGEvent(mouseEventSource: src, mouseType: .otherMouseDragged, mouseCursorPosition: p,
                        mouseButton: CGMouseButton(rawValue: UInt32(n))!)!
        e.setIntegerValueField(.mouseEventButtonNumber, value: n)
        e.setIntegerValueField(.eventSourceUserData, value: 0x7E57)
        e.post(tap: .cghidEventTap)
    }

    var failures = 0
    func check(_ ok: Bool, _ name: String, _ detail: String) {
        print("\(ok ? "PASS" : "FAIL")  \(name) — \(detail)")
        if !ok { failures += 1 }
    }
    func scrolls(_ l: [Seen]) -> [Seen] { l.filter { $0.type == .scrollWheel && $0.marked } }
    func raw(_ l: [Seen]) -> [Seen] { l.filter { !$0.marked } }

    let here = CGEvent(source: nil)!.location
    func want(_ s: String, visual: Bool = false) -> Bool { scenarios.isEmpty ? !visual : scenarios.contains(s) }
    _ = obs.take(); spin(0.3); _ = obs.take()

    if want("scroll") {
        tick(-1); spin(0.8)
        let l = obs.take(); let s = scrolls(l)
        let total = s.reduce(0) { $0 + $1.pixDY }
        let phases = s.map(\.phase)
        check(raw(l).filter { $0.type == .scrollWheel }.isEmpty, "wheel tick is swallowed", "\(describe(raw(l)))")
        check(s.count >= 5, "tick becomes a smooth stream", "\(s.count) pixel events")
        check(abs(total + 64) <= 1, "one tick = 64px (Medium)", "total \(total)px")
        check(s.allSatisfy { $0.continuous == 1 }, "output is pixel-precise", "continuous flags \(Set(s.map(\.continuous)))")
        check(phases.first == 1 && phases.last == 4 && phases.dropFirst().dropLast().allSatisfy { $0 == 2 },
              "trackpad phases began→changed→ended", "\(phases.first ?? -1)…\(phases.last ?? -1)")
        if let a = s.first, let b = s.last { print("      duration \(String(format: "%.0f", (b.t - a.t) * 1000))ms, first step \(a.pixDY)px") }
    }

    if want("accel") {
        for _ in 0..<8 { tick(-1); spin(0.03) }
        spin(1.2)
        let total = scrolls(obs.take()).reduce(0) { $0 + $1.pixDY }
        check(total < -8 * 64 * 1.3, "fast flicks accelerate", "8 ticks → \(Int(total))px (no-accel would be \(-8 * 64))")
    }

    if want("reverse-dir") {
        tick(-1); spin(0.02); tick(1); spin(0.8)
        let s = scrolls(obs.take())
        let up = s.filter { $0.pixDY > 0 }.reduce(0) { $0 + $1.pixDY }
        check(abs(up - 64) <= 1, "direction change responds immediately", "up \(up)px")
    }

    if want("shift") {
        tick(-1, flags: .maskShift); spin(0.8)
        let s = scrolls(obs.take())
        let dx = s.reduce(0) { $0 + $1.pixDX }, dy = s.reduce(0) { $0 + $1.pixDY }
        check(abs(dx + 64) <= 1 && dy == 0, "⇧ scrolls horizontally", "dx \(dx) dy \(dy)")
    }

    if want("option") {
        tick(-1, flags: .maskAlternate); spin(0.6)
        let total = scrolls(obs.take()).reduce(0) { $0 + $1.pixDY }
        check(abs(total + 8) <= 1, "⌥ scrolls precisely", "\(total)px")
    }

    if want("control") {
        tick(-1, flags: .maskControl); spin(0.8)
        let total = scrolls(obs.take()).reduce(0) { $0 + $1.pixDY }
        check(abs(total + 160) <= 1, "⌃ scrolls swiftly", "\(total)px")
    }

    if want("command") {
        tick(1, flags: .maskCommand); spin(0.4)
        let keys = obs.take().filter { $0.type == .keyDown && $0.marked }
        check(keys.count == 1 && keys[0].key == 24 && keys[0].flags.contains(.maskCommand), "⌘ + wheel up = zoom in (⌘=)",
              "keys \(keys.map { $0.key })")
    }

    if want("back") {
        button(3, down: true, at: here); spin(0.06); button(3, down: false, at: here); spin(0.3)
        let l = obs.take()
        let keys = l.filter { $0.type == .keyDown && $0.marked }
        check(keys.count == 1 && keys[0].key == 33 && keys[0].flags.contains(.maskCommand), "button 4 click = Back (⌘[)", "keys \(keys.map { $0.key })")
        check(raw(l).filter { $0.type == .otherMouseDown }.isEmpty, "button 4 press is consumed", describe(l))
        if let k = keys.first { print("      latency after release: \(String(format: "%.0f", (k.t - l.first!.t) * 1000))ms") }
    }

    if want("forward") {
        button(4, down: true, at: here); spin(0.06); button(4, down: false, at: here); spin(0.3)
        let keys = obs.take().filter { $0.type == .keyDown && $0.marked }
        check(keys.map(\.key) == [30], "button 5 click = Forward (⌘])", "keys \(keys.map { $0.key })")
    }

    if want("hold") {
        // Button 4 hold = Show Desktop (Dock action, not a key) — so Back must NOT fire.
        button(3, down: true, at: here); spin(0.5)
        let during = obs.take()
        button(3, down: false, at: here); spin(0.4)
        let after = obs.take()
        let keys = (during + after).filter { $0.type == .keyDown && $0.marked }
        check(keys.isEmpty, "button 4 hold does not also click Back", "keys \(keys.map { $0.key })")
        // Toggle Show Desktop back off.
        button(3, down: true, at: here); spin(0.5); button(3, down: false, at: here); spin(0.4); _ = obs.take()
    }

    if want("middle") {
        button(2, down: true, at: here); spin(0.06); button(2, down: false, at: here); spin(0.3)
        let l = obs.take()
        let reposted = l.filter { $0.marked && ($0.type == .otherMouseDown || $0.type == .otherMouseUp) && $0.button == 2 }
        check(reposted.count == 2, "middle click still works (re-delivered)", describe(l))
    }

    if want("middle-drag") {
        button(2, down: true, at: here); spin(0.03)
        for i in 1...6 { drag(2, to: CGPoint(x: here.x + Double(i * 5), y: here.y)); spin(0.01) }
        button(2, down: false, at: CGPoint(x: here.x + 30, y: here.y)); spin(0.3)
        let l = obs.take()
        let syntheticDown = l.filter { $0.marked && $0.type == .otherMouseDown && $0.button == 2 }
        let drags = raw(l).filter { $0.type == .otherMouseDragged }
        let ups = raw(l).filter { $0.type == .otherMouseUp }
        check(syntheticDown.count == 1 && drags.count >= 4 && ups.count == 1, "middle-drag passes through", "down \(syntheticDown.count), drags \(drags.count), up \(ups.count)")
    }

    if want("unmapped") {
        button(5, down: true, at: here); spin(0.05); button(5, down: false, at: here); spin(0.2)
        let l = obs.take()
        check(raw(l).count == 2 && l.filter(\.marked).isEmpty, "unmapped button 6 is untouched", "raw \(raw(l).count), glide \(l.filter(\.marked).count)")
    }

    if want("missioncontrol", visual: true) {
        button(2, down: true, at: here); spin(0.6); button(2, down: false, at: here); spin(1.2)
        print("      (Mission Control should now be open)")
    }

    print(failures == 0 ? "\nALL LIVE TESTS PASSED" : "\n\(failures) LIVE TEST(S) FAILED")
    return failures == 0 ? 0 : 1
}
