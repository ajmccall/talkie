import AppKit

enum Sounds {
    static func recordingStarted() { play("Tink") }
    static func recordingStopped() { play("Pop") }
    static func capApproaching() { play("Purr") }
    static func pasted() { play("Glass") }
    static func failed() { play("Basso") }

    private static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
