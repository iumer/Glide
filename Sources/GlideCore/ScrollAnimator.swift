import Foundation

public struct ScrollParams: Equatable {
    public var pixelsPerTick: Double
    /// Extra multiplier added per consecutive fast tick (0 = no acceleration).
    public var acceleration: Double
    /// Ease-out time constant in seconds (0 = deliver instantly).
    public var timeConstant: Double

    public init(pixelsPerTick: Double, acceleration: Double, timeConstant: Double) {
        self.pixelsPerTick = pixelsPerTick
        self.acceleration = acceleration
        self.timeConstant = timeConstant
    }
}

/// Turns discrete wheel ticks into a smooth stream of whole-pixel deltas.
///
/// Each tick adds distance to a "remaining" budget; every frame moves a fraction
/// `1 - e^(-dt/τ)` of what is left (exponential ease-out), carrying sub-pixel
/// remainders so the total delivered equals the total requested (±1px).
public final class ScrollAnimator {
    public private(set) var remainingX = 0.0
    public private(set) var remainingY = 0.0
    public private(set) var streak = 0
    private var carryX = 0.0
    private var carryY = 0.0
    private var lastTick = -1.0
    private var lastSignX = 0.0
    private var lastSignY = 0.0

    /// Ticks closer together than this extend the acceleration streak.
    public var fastGap = 0.12
    /// A pause longer than this resets the streak.
    public var resetGap = 0.35
    public var maxStreak = 18

    public init() {}

    public var isIdle: Bool { remainingX == 0 && remainingY == 0 }

    public func reset() {
        remainingX = 0; remainingY = 0; carryX = 0; carryY = 0
        streak = 0; lastSignX = 0; lastSignY = 0
    }

    /// - Parameters: dx/dy are wheel ticks (lines), already sign-corrected.
    public func addTick(dx: Double, dy: Double, at t: Double, params p: ScrollParams) {
        let gap = lastTick < 0 ? .infinity : t - lastTick
        lastTick = t
        let sx = dx == 0 ? 0 : (dx > 0 ? 1.0 : -1.0)
        let sy = dy == 0 ? 0 : (dy > 0 ? 1.0 : -1.0)
        let reversed = (sy != 0 && lastSignY != 0 && sy != lastSignY) ||
            (sx != 0 && lastSignX != 0 && sx != lastSignX)
        if reversed {
            // Direction change: drop what is left so the page responds immediately.
            remainingX = 0; remainingY = 0; carryX = 0; carryY = 0; streak = 0
        } else if gap < fastGap {
            streak = min(streak + 1, maxStreak)
        } else if gap > resetGap {
            streak = 0
        }
        if sx != 0 { lastSignX = sx }
        if sy != 0 { lastSignY = sy }

        let multiplier = 1 + p.acceleration * Double(streak)
        remainingX += dx * p.pixelsPerTick * multiplier
        remainingY += dy * p.pixelsPerTick * multiplier
    }

    /// Advance by `dt` seconds; returns whole pixels to post this frame.
    public func step(dt: Double, timeConstant tau: Double) -> (x: Int, y: Int) {
        var mx = remainingX
        var my = remainingY
        if tau > 0 {
            let f = 1 - exp(-max(dt, 0) / tau)
            mx = remainingX * f
            my = remainingY * f
            // Snap the tail so the animation terminates.
            if abs(remainingX - mx) < 0.5 { mx = remainingX }
            if abs(remainingY - my) < 0.5 { my = remainingY }
        }
        remainingX -= mx
        remainingY -= my
        carryX += mx
        carryY += my
        let ix = carryX.rounded(.towardZero)
        let iy = carryY.rounded(.towardZero)
        carryX -= ix
        carryY -= iy
        if isIdle {
            // Flush the last fractional pixel so totals stay exact.
            let fx = carryX.rounded(), fy = carryY.rounded()
            carryX = 0; carryY = 0
            return (Int(ix + fx), Int(iy + fy))
        }
        return (Int(ix), Int(iy))
    }
}
