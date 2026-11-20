import AppKit
import ApplicationServices
import CoreGraphics

/// Watches the hardware fn (globe) key through a HID-level event tap.
///
/// fn alone produces no characters, which makes it the perfect push-to-talk key —
/// but macOS likes to bind it to the emoji picker, so the flagsChanged events are
/// swallowed here. Any other key pressed while fn is held cancels the recording,
/// which keeps fn+arrow / fn+F3 style shortcuts usable.
final class FnKeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fnHeld = false

    private static let fnKeyCode: Int64 = 63

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: fnEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        fnHeld = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if fnHeld {
                fnHeld = false
                onCancel?()
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let holding = event.flags.contains(.maskSecondaryFn)
            if holding && !fnHeld {
                fnHeld = true
                onPress?()
                return nil // swallow so macOS does not open the emoji picker
            }
            if !holding && fnHeld {
                fnHeld = false
                onRelease?()
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            if fnHeld {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                if code != Self.fnKeyCode {
                    fnHeld = false
                    onCancel?()
                }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

private let fnEventCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
