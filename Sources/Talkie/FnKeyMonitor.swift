import AppKit

/// Watches the Fn (Globe) key. macOS reports it as a modifier, so it never produces
/// keyDown/keyUp; instead `.flagsChanged` fires with the `.function` flag toggling.
///
/// Global monitoring of keyboard events requires the Accessibility permission.
/// A monitor installed before that permission is granted never receives events,
/// so the owner must call `restart()` once the grant lands.
///
/// Shift is tracked across the hold: `onRelease` reports whether Shift was down
/// at any point while Fn was held, which Talkie uses to request a processor.
@MainActor
final class FnKeyMonitor {
    static let fnKeyCode: UInt16 = 63

    var onPress: (() -> Void)?
    /// Called on Fn release with whether Shift was held at any point during the hold.
    var onRelease: ((Bool) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var isDown = false
    private(set) var shiftSeen = false

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isDown = false
        shiftSeen = false
    }

    func restart() {
        stop()
        start()
    }

    private func handle(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        if isDown, shift { shiftSeen = true }
        guard event.keyCode == Self.fnKeyCode else { return }
        let down = event.modifierFlags.contains(.function)
        guard down != isDown else { return }
        isDown = down
        if down {
            shiftSeen = shift
            onPress?()
        } else {
            let requested = shiftSeen
            shiftSeen = false
            onRelease?(requested)
        }
    }
}
