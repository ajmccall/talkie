import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    /// Whether the transcript is passed through the local LLM before pasting.
    static var cleanupEnabled: Bool {
        get { defaults.object(forKey: "cleanupEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "cleanupEnabled") }
    }

    /// The Welcome window has been shown once on first launch.
    static var welcomeShown: Bool {
        get { defaults.bool(forKey: "welcomeShown") }
        set { defaults.set(newValue, forKey: "welcomeShown") }
    }

    /// Which set of sounds plays for start, stop, paste and failure.
    static var soundTheme: SoundTheme {
        get { defaults.string(forKey: "soundTheme").flatMap(SoundTheme.init(rawValue:)) ?? .chime }
        set { defaults.set(newValue.rawValue, forKey: "soundTheme") }
    }

    static var soundVolume: SoundVolume {
        get { defaults.string(forKey: "soundVolume").flatMap(SoundVolume.init(rawValue:)) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "soundVolume") }
    }

    /// Names and terms Parakeet should prefer, with their known mis-hearings.
    static var vocabulary: [VocabularyTerm] {
        get { Vocabulary.decode(defaults.data(forKey: "vocabulary")) }
        set { defaults.set(Vocabulary.encode(newValue), forKey: "vocabulary") }
    }

    /// How many paste messages have pointed at Fix Last Dictation so far.
    static var fixHintsShown: Int {
        get { defaults.integer(forKey: "fixHintsShown") }
        set { defaults.set(newValue, forKey: "fixHintsShown") }
    }

    /// The hint stops after this many plain pastes; the menu item stays.
    static let fixHintCount = 10

    // MARK: - Optional skill post-processing (Fn+Shift)

    /// The connected model account, or nil when skills are off.
    static var providerKind: ProviderKind? {
        get { defaults.string(forKey: "provider").flatMap(ProviderKind.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "provider") }
    }

    /// Explicit CLI path chosen by the user for one provider; empty means auto-detect.
    /// Earlier versions stored a single path, which belonged to Codex.
    static func providerExecutableOverride(for kind: ProviderKind) -> String? {
        defaults.string(forKey: "providerExecutable.\(kind.rawValue)")
            ?? (kind == .codex ? defaults.string(forKey: "providerExecutable") : nil)
    }

    static func setProviderExecutableOverride(_ path: String?, for kind: ProviderKind) {
        defaults.set(path, forKey: "providerExecutable.\(kind.rawValue)")
        if kind == .codex { defaults.removeObject(forKey: "providerExecutable") }
    }

    /// Claude Code keeps its login in a config folder (`~/.claude` unless
    /// `CLAUDE_CONFIG_DIR` is set in the shell). Talkie is not launched from a
    /// shell, so a non-default folder is chosen here.
    static var claudeConfigDirectory: String? {
        get { defaults.string(forKey: "claudeConfigDirectory") }
        set { defaults.set(newValue, forKey: "claudeConfigDirectory") }
    }

    static var providerModel: String {
        get { defaults.string(forKey: "providerModel") ?? providerKind?.defaultModel ?? "" }
        set { defaults.set(newValue, forKey: "providerModel") }
    }

    /// SKILL.md files offered by the Fn+Shift picker, in the order added.
    /// Seeds itself from the single `skillPath` setting of earlier versions.
    static var skillPaths: [String] {
        get {
            let stored = defaults.stringArray(forKey: "skillPaths") ?? []
            let migrated = SkillList.migrate(legacy: defaults.string(forKey: "skillPath"), existing: stored)
            if migrated != stored {
                defaults.set(migrated, forKey: "skillPaths")
                defaults.removeObject(forKey: "skillPath")
            }
            return migrated
        }
        set { defaults.set(newValue, forKey: "skillPaths") }
    }

    /// Highlighted first in the picker next time.
    static var lastUsedSkillPath: String? {
        get { defaults.string(forKey: "lastUsedSkill") }
        set { defaults.set(newValue, forKey: "lastUsedSkill") }
    }

    static var preselectedSkillPath: String? {
        SkillList.preselected(paths: skillPaths, lastUsed: lastUsedSkillPath)
    }

    static var skillChoices: [SkillChoice] {
        skillPaths.map { SkillChoice(path: $0, name: SkillPrompt.name(ofSkillAt: $0)) }
    }

    static var skillEnabled: Bool { providerKind != nil && !skillPaths.isEmpty }

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

    /// A CLI pre-launched on Fn+Shift is used only if it is younger than this;
    /// an older one (a very long hold) is killed and a fresh one launched.
    static let warmTransformMaximumAgeSeconds: TimeInterval = 60

    /// Delay between putting text on the clipboard and sending ⌘V. Some apps
    /// (Electron, Java) need a moment to notice the new pasteboard contents.
    static let pasteDelayMilliseconds = 80

    /// Longer delay after the skill picker closes: it held keyboard focus, and the
    /// app underneath needs a moment to get it back before ⌘V arrives.
    static let pickerPasteDelayMilliseconds = 150
}
