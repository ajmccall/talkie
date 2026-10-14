import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    /// Whether the transcript is passed through the local LLM before pasting.
    static var cleanupEnabled: Bool {
        get { defaults.object(forKey: "cleanupEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cleanupEnabled") }
    }

    /// Presses shorter than this are treated as accidental and ignored.
    static let minimumHoldSeconds: TimeInterval = 0.25

    /// Recordings shorter than this are discarded without transcribing.
    static let minimumAudioSeconds: TimeInterval = 0.5

    /// Recording stops on its own after this long, even if Fn is still held,
    /// so a stuck key cannot fill memory indefinitely.
    static let maximumRecordingSeconds: TimeInterval = 300

    /// If the LLM has not answered within this time, the raw transcript is pasted.
    static let cleanupTimeoutSeconds: TimeInterval = 20

    /// Delay between putting text on the clipboard and sending ⌘V. Some apps
    /// (Electron, Java) need a moment to notice the new pasteboard contents.
    static let pasteDelayMilliseconds = 80
}
