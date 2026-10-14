import AppKit

/// Watches the Fn (Globe) key. macOS reports it as a modifier, so it never produces
/// keyDown/keyUp; instead `.flagsChanged` fires with the `.function` flag toggling.
///
/// Global monitoring of keyboard events requires the Accessibility permission.
/// A monitor installed before that permission is granted never receives events,
/// so the owner must call `restart()` once the grant lands.
@MainActor
final class FnKeyMonitor {
    static let fnKeyCode: UInt16 = 63

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var isDown = false

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
    }

    func restart() {
        stop()
        start()
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == Self.fnKeyCode else { return }
        let down = event.modifierFlags.contains(.function)
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }
}
