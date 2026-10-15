import Foundation

/// Deterministic post-processing applied after the LLM (or to the raw transcript
/// when cleanup is off). Add rules here for things that should always happen
/// regardless of what the model does. Names and terms belong in the Vocabulary
/// window instead: that pass listens to the audio rather than editing text.
enum TextRules {
    typealias Rule = (String) -> String

    static let rules: [Rule] = [
        collapseWhitespace,
        trim,
    ]

    static func apply(_ text: String) -> String {
        rules.reduce(text) { $1($0) }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
