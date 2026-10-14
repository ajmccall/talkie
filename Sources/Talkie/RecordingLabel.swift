import Foundation

/// Text for the HUD while recording. Plain "Listening…" for most of the
/// recording; an amber countdown once the maximum length is close.
enum RecordingLabel {
    struct Label: Equatable {
        let text: String
        let nearCap: Bool
    }

    /// "m:ss", floored to whole seconds.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    static func label(
        elapsed: TimeInterval,
        cap: TimeInterval = Settings.maximumRecordingSeconds,
        warnBefore: TimeInterval = Settings.warningBeforeCapSeconds,
        skill: String? = nil
    ) -> Label {
        let suffix = skill.map { " · \($0)" } ?? ""
        let shown = min(elapsed, cap)
        guard shown >= cap - warnBefore else {
            return Label(text: "Listening…\(suffix)", nearCap: false)
        }
        return Label(text: "Listening… \(clock(shown)) · stops at \(clock(cap))\(suffix)", nearCap: true)
    }
}
