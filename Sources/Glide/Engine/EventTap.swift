import CoreGraphics
import Foundation

/// Marker written into `eventSourceUserData` on every event Glide posts,
/// so the tap never re-processes its own output.
let glideEventMarker: Int64 = 0x474C_4944_45 // "GLIDE"

/// A session-wide CGEventTap running on its own thread so heavy UI work never stalls input.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private let handler: Handler
    private let mask: CGEventMask

    init(mask: CGEventMask, handler: @escaping Handler) {
        self.mask = mask
        self.handler = handler
    }

    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // macOS turns slow taps off; switch ourselves back on.
                if let p = me.port { CGEvent.tapEnable(tap: p, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.handler(type, event)
        }
        guard let p = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        port = p

        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            guard let self, let p = self.port else { ready.signal(); return }
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, p, 0)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.runLoop, src, .commonModes)
            CGEvent.tapEnable(tap: p, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "Glide.EventTap"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
        return true
    }

    func stop() {
        if let p = port {
            CGEvent.tapEnable(tap: p, enable: false)
            CFMachPortInvalidate(p)
        }
        if let rl = runLoop { CFRunLoopStop(rl) }
        port = nil
        runLoop = nil
        thread = nil
    }
}

extension CGEventType {
    var maskBit: CGEventMask { CGEventMask(1) << CGEventMask(rawValue) }
}
