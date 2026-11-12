import CoreGraphics
import Foundation
import GlideCore

/// Turns extra mouse buttons (3, 4, 5, …) into actions with click / double-click / hold triggers.
final class ButtonController {
    private let queue = DispatchQueue(label: "Glide.buttons", qos: .userInteractive)
    private var detectors: [Int: ClickDetector] = [:] // queue only

    // Shared between the tap thread and `queue`.
    private let lock = NSLock()
    private var downLocation: [Int: CGPoint] = [:]
    private var dragPassthrough: Set<Int> = []
    private var holdFired: Set<Int> = []
    private var swallowNextUp: Set<Int> = []
    private var captureHandler: ((Int) -> Void)?

    /// Next press of any extra button is reported here instead of being acted on.
    func captureNextButton(_ handler: ((Int) -> Void)?) {
        lock.withLock { captureHandler = handler }
    }

    func handle(_ type: CGEventType, _ event: CGEvent, settings s: GlideSettings) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1

        if type == .otherMouseDown, let cb = lock.withLock({ () -> ((Int) -> Void)? in
            let h = captureHandler; captureHandler = nil
            if h != nil { swallowNextUp.insert(button) }
            return h
        }) {
            DispatchQueue.main.async { cb(button) }
            return nil
        }
        if type == .otherMouseUp, lock.withLock({ swallowNextUp.remove(button) != nil }) { return nil }

        guard s.buttonsEnabled, let config = s.clickConfig(for: button) else { return pass }

        switch type {
        case .otherMouseDown:
            lock.withLock {
                downLocation[button] = event.location
                dragPassthrough.remove(button)
                holdFired.remove(button)
            }
            let now = ProcessInfo.processInfo.systemUptime
            queue.async { [self] in
                let d = detector(button, config)
                deliver(d.down(at: now), button: button, settings: s)
                schedule(d, button: button, settings: s)
            }
            return nil

        case .otherMouseDragged:
            let startDrag: CGPoint? = lock.withLock {
                guard !dragPassthrough.contains(button), !holdFired.contains(button),
                      let p = downLocation[button] else { return nil }
                let dist = hypot(event.location.x - p.x, event.location.y - p.y)
                guard dist > 6 else { return nil }
                dragPassthrough.insert(button)
                return p
            }
            if let origin = startDrag {
                // The user is dragging (e.g. middle-click pan): give the app the press we held back.
                queue.async { [self] in detectors[button]?.reset() }
                Actions.postButton(button, down: true, at: origin)
                return pass
            }
            return lock.withLock { dragPassthrough.contains(button) } ? pass : nil

        case .otherMouseUp:
            if lock.withLock({ dragPassthrough.remove(button) != nil }) { return pass }
            let now = ProcessInfo.processInfo.systemUptime
            queue.async { [self] in
                let d = detector(button, config)
                deliver(d.up(at: now), button: button, settings: s)
                schedule(d, button: button, settings: s)
            }
            return nil

        default:
            return pass
        }
    }

    // MARK: queue-confined

    private func detector(_ button: Int, _ config: ClickConfig) -> ClickDetector {
        if let d = detectors[button] {
            d.config = config
            return d
        }
        let d = ClickDetector(config: config)
        detectors[button] = d
        return d
    }

    private func schedule(_ d: ClickDetector, button: Int, settings s: GlideSettings) {
        guard let deadline = d.nextDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.002
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            deliver(d.tick(at: ProcessInfo.processInfo.systemUptime), button: button, settings: s)
            schedule(d, button: button, settings: s)
        }
    }

    private func deliver(_ outputs: [ClickOutput], button: Int, settings s: GlideSettings) {
        for o in outputs {
            switch o {
            case .click: if let m = s.mapping(button: button, trigger: .click) { Actions.perform(m) }
            case .doubleClick: if let m = s.mapping(button: button, trigger: .doubleClick) { Actions.perform(m) }
            case .hold:
                lock.withLock { _ = holdFired.insert(button) }
                if let m = s.mapping(button: button, trigger: .hold) { Actions.perform(m) }
            case .passthrough:
                let p = lock.withLock { downLocation[button] }
                Actions.postClick(button: button, at: p)
            }
        }
    }
}
