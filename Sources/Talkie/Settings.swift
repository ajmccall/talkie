import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    /// Whether the transcript is passed through the local LLM before pasting.
    static var cleanupEnabled: Bool {
        get { defaults.object(forKey: "cleanupEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cleanupEnabled") }
    }

    // MARK: - Optional skill post-processing (Fn+Shift)

    /// The connected model account, or nil when skills are off.
    static var providerKind: ProviderKind? {
        get { defaults.string(forKey: "provider").flatMap(ProviderKind.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "provider") }
    }

    /// Explicit CLI path chosen by the user; empty means auto-detect.
    static var providerExecutableOverride: String? {
        get { defaults.string(forKey: "providerExecutable") }
        set { defaults.set(newValue, forKey: "providerExecutable") }
    }

    static var providerModel: String {
        get { defaults.string(forKey: "providerModel") ?? providerKind?.defaultModel ?? "" }
        set { defaults.set(newValue, forKey: "providerModel") }
    }

    /// Path to the SKILL.md applied on Fn+Shift.
    static var skillPath: String? {
        get { defaults.string(forKey: "skillPath") }
        set { defaults.set(newValue, forKey: "skillPath") }
    }

    static var skillEnabled: Bool { providerKind != nil && skillPath != nil }

    /// Presses shorter than this are treated as accidental and ignored.
    static let minimumHoldSeconds: TimeInterval = 0.25

    /// Recordings shorter than this are discarded without transcribing.
    static let minimumAudioSeconds: TimeInterval = 0.5

    /// Recording stops on its own after this long, even if Fn is still held,
    /// so a stuck key cannot fill memory indefinitely.
    static let maximumRecordingSeconds: TimeInterval = 300

    /// The HUD switches to an amber countdown this long before the cap.
    static let warningBeforeCapSeconds: TimeInterval = 30

    /// If the LLM has not answered within this time, the raw transcript is pasted.
    /// A full 5-minute recording measured 15.8 s on an M4 Pro, so 20 s left no
    /// headroom for slower Macs.
    static let cleanupTimeoutSeconds: TimeInterval = 30

    /// If the skill provider has not answered within this time, the cleaned
    /// transcript is pasted. Codex takes 5–20 s on a short message.
    static let skillTimeoutSeconds: TimeInterval = 90

    /// Delay between putting text on the clipboard and sending ⌘V. Some apps
    /// (Electron, Java) need a moment to notice the new pasteboard contents.
    static let pasteDelayMilliseconds = 80
}
