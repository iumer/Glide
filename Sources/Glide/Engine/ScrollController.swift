import CoreGraphics
import Foundation
import GlideCore

/// Swallows line-based wheel ticks and re-emits them as smooth pixel scrolling.
final class ScrollController {
    private enum Mode { case normal, precise, swift }

    private let queue = DispatchQueue(label: "Glide.scroll", qos: .userInteractive)
    private let animator = ScrollAnimator()
    private var timer: DispatchSourceTimer?
    private var lastFrame = 0.0
    private var timeConstant = 0.0
    private var trackpadLike = false
    private var gestureActive = false
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Called on the event-tap thread. Return nil to swallow the event.
    func handle(_ event: CGEvent, settings s: GlideSettings) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        guard s.scrollEnabled else { return pass }
        // Leave trackpads, Magic Mouse and anything already pixel-precise alone.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return pass }
        if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 { return pass }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return pass }

        var dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if dx == 0 && dy == 0 { return pass }

        let flags = event.flags
        if s.zoomModifier && flags.contains(.maskCommand) {
            let zoomIn = (dy != 0 ? dy : dx) > 0
            queue.async { Actions.zoom(in: zoomIn) }
            return nil
        }

        if s.reverseDirection { dx = -dx; dy = -dy }
        if s.horizontalModifier && flags.contains(.maskShift) && dx == 0 { dx = dy; dy = 0 }

        var mode = Mode.normal
        if s.preciseModifier && flags.contains(.maskAlternate) { mode = .precise }
        else if s.swiftModifier && flags.contains(.maskControl) { mode = .swift }

        var params = ScrollParams(
            pixelsPerTick: s.speed.pixelsPerTick,
            acceleration: s.acceleration ? 0.22 : 0,
            timeConstant: s.smoothness.timeConstant
        )
        switch mode {
        case .normal: break
        case .precise: params.pixelsPerTick = 8; params.acceleration = 0; params.timeConstant = min(params.timeConstant, 0.05)
        case .swift: params.pixelsPerTick *= 2.5; params.acceleration *= 2
        }

        let now = ProcessInfo.processInfo.systemUptime
        let trackpad = s.trackpadLike
        queue.async { [self] in
            animator.addTick(dx: dx, dy: dy, at: now, params: params)
            timeConstant = params.timeConstant
            trackpadLike = trackpad
            if params.timeConstant == 0 {
                let (x, y) = animator.step(dt: 0, timeConstant: 0)
                post(x: x, y: y, phase: nil)
            } else {
                startTimerIfNeeded()
            }
        }
        return nil
    }

    // MARK: Animation loop (runs on `queue`)

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .microseconds(300))
        t.setEventHandler { [weak self] in self?.frame() }
        lastFrame = ProcessInfo.processInfo.systemUptime
        timer = t
        t.resume()
    }

    private func frame() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastFrame, 0.05)
        lastFrame = now
        let (x, y) = animator.step(dt: dt, timeConstant: timeConstant)
        if x != 0 || y != 0 {
            post(x: x, y: y, phase: trackpadLike ? (gestureActive ? .changed : .began) : nil)
            gestureActive = trackpadLike
        }
        if animator.isIdle {
            if gestureActive { post(x: 0, y: 0, phase: .ended) }
            gestureActive = false
            timer?.cancel()
            timer = nil
        }
    }

    private enum Phase: Int64 { case began = 1, changed = 2, ended = 4 }

    private func post(x: Int, y: Int, phase: Phase?) {
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                              wheelCount: 2, wheel1: Int32(y), wheel2: Int32(x), wheel3: 0) else { return }
        e.flags = []
        e.setIntegerValueField(.eventSourceUserData, value: glideEventMarker)
        if let phase {
            // Phases make apps treat the stream like a trackpad gesture (rubber-banding, etc.).
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.rawValue)
        }
        e.post(tap: .cgSessionEventTap)
    }
}
