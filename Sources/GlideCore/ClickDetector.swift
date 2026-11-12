import Foundation

public struct ClickConfig: Equatable {
    public var hasClick: Bool
    public var hasDouble: Bool
    public var hasHold: Bool
    public var holdDelay: Double = 0.35
    public var doubleWindow: Double = 0.25
    public init(hasClick: Bool, hasDouble: Bool, hasHold: Bool) {
        self.hasClick = hasClick
        self.hasDouble = hasDouble
        self.hasHold = hasHold
    }
}

public enum ClickOutput: Equatable {
    case click, doubleClick, hold
    /// The press had no action of its own — re-deliver a normal button click.
    case passthrough
}

/// Per-button state machine that turns raw down/up events into click / double / hold.
/// Time is injected so it can be tested deterministically.
public final class ClickDetector {
    enum State: Equatable {
        case idle
        case firstDown(start: Double)
        case waitingForSecond(deadline: Double)
        case secondDown
        case holdFired
    }

    private(set) var state: State = .idle
    public var config: ClickConfig

    public init(config: ClickConfig) { self.config = config }

    public var holdHasFired: Bool { state == .holdFired }

    /// When the caller should call `tick` next, if anything is pending.
    public var nextDeadline: Double? {
        switch state {
        case let .firstDown(start) where config.hasHold: return start + config.holdDelay
        case let .waitingForSecond(deadline): return deadline
        default: return nil
        }
    }

    public func reset() { state = .idle }

    public func down(at t: Double) -> [ClickOutput] {
        switch state {
        case .waitingForSecond: state = .secondDown
        default: state = .firstDown(start: t)
        }
        return []
    }

    public func up(at t: Double) -> [ClickOutput] {
        switch state {
        case .firstDown:
            if config.hasDouble {
                state = .waitingForSecond(deadline: t + config.doubleWindow)
                return []
            }
            state = .idle
            return [config.hasClick ? .click : .passthrough]
        case .secondDown:
            state = .idle
            return [.doubleClick]
        case .holdFired:
            state = .idle
            return []
        case .idle, .waitingForSecond:
            return []
        }
    }

    public func tick(at t: Double) -> [ClickOutput] {
        switch state {
        case let .firstDown(start) where config.hasHold && t - start >= config.holdDelay:
            state = .holdFired
            return [.hold]
        case let .waitingForSecond(deadline) where t >= deadline:
            state = .idle
            return [config.hasClick ? .click : .passthrough]
        default:
            return []
        }
    }
}
