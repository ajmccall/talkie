import Foundation

/// One finished dictation, kept in memory only until the next one lands, so a
/// mis-heard word can be added to the vocabulary and checked against the same
/// audio. Nothing is written to disk.
struct DictationRecord: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let recording: AudioRecorder.Recording
    /// Parakeet's output after the vocabulary pass, before Qwen3 or a skill.
    let raw: String
    let fixes: [Transcription.Fix]
    /// What was pasted.
    let text: String
    /// The paste message, e.g. "Pasted (fixed Alfie)".
    let outcome: String

    init(date: Date = Date(), recording: AudioRecorder.Recording, raw: String, fixes: [Transcription.Fix], text: String, outcome: String) {
        id = UUID()
        self.date = date
        self.recording = recording
        self.raw = raw
        self.fixes = fixes
        self.text = text
        self.outcome = outcome
    }
}

/// Pure helpers behind the Fix Last Dictation window: the transcript as
/// clickable words, the selection rule, and the verdict after listening again.
enum Correction {
    /// One word of the raw transcript. `display` keeps its punctuation so the
    /// text reads naturally; `word` is what goes into the alias.
    struct Chip: Equatable, Identifiable, Sendable {
        let id: Int
        let display: String
        let word: String
    }

    static func chips(_ text: String) -> [Chip] {
        text.split(whereSeparator: \.isWhitespace).enumerated().map { index, piece in
            Chip(id: index, display: String(piece), word: stripPunctuation(String(piece)))
        }
    }

    /// Click rule for a single contiguous selection: a click next to the range
    /// extends it, a click on either end shrinks it, a click on the only
    /// selected word clears it, and anything else starts a new selection there.
    static func toggle(_ index: Int, in selection: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let selection else { return index...index }
        if selection.lowerBound == index, selection.upperBound == index { return nil }
        if index == selection.lowerBound - 1 { return index...selection.upperBound }
        if index == selection.upperBound + 1 { return selection.lowerBound...index }
        if index == selection.lowerBound { return (index + 1)...selection.upperBound }
        if index == selection.upperBound { return selection.lowerBound...(index - 1) }
        return index...index
    }

    /// The selected words joined with spaces ("Rath mines"), or nil when
    /// nothing is selected.
    static func heard(_ selection: ClosedRange<Int>?, in chips: [Chip]) -> String? {
        guard let selection else { return nil }
        let words = chips.filter { selection.contains($0.id) }.map(\.word).filter { !$0.isEmpty }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// What listening again with the new spelling produced.
    enum Verdict: Equatable, Sendable {
        /// The vocabulary pass swapped something for the term.
        case fixed(term: String)
        /// The term was already in the transcript; nothing needed swapping.
        case alreadyCorrect(term: String)
        /// The term did not appear. `heard` is the alias if it is still there.
        case stillWrong(term: String, heard: String?)

        var isGood: Bool {
            switch self {
            case .fixed, .alreadyCorrect: return true
            case .stillWrong: return false
            }
        }

        var message: String {
            switch self {
            case .fixed(let term):
                return "Now hears “\(term)” in this recording"
            case .alreadyCorrect(let term):
                return "Talkie already writes “\(term)” here; it will now prefer that spelling"
            case .stillWrong(let term, let heard?):
                return "Still hears “\(heard)”: try adding another spelling of \(term)"
            case .stillWrong(let term, nil):
                return "Still does not hear “\(term)”: try adding another spelling"
            }
        }
    }

    /// Compares on lowercased, punctuation-stripped words, because
    /// `Fix.original` keeps trailing punctuation ("Ratminds.").
    static func verdict(term: String, alias: String, after: Transcription) -> Verdict {
        let termWords = words(term)
        if after.fixes.contains(where: { words($0.term) == termWords }) { return .fixed(term: term) }
        let textWords = words(after.text)
        if contains(textWords, phrase: termWords) { return .alreadyCorrect(term: term) }
        let aliasWords = words(alias)
        let heard = !aliasWords.isEmpty && contains(textWords, phrase: aliasWords) ? alias : nil
        return .stillWrong(term: term, heard: heard)
    }

    // MARK: - Paste message hint

    static let hintSuffix = " (wrong word? Fix Last Dictation in the menu)"

    /// Appended to a plain "Pasted" for the first few dictations so the fix flow
    /// is discovered. Raw fallbacks, skill pastes and pastes that already report
    /// a fix carry their own message instead.
    static func hudHint(pastesSoFar: Int, outcome: CleanupOutcome, skill: SkillOutcome, fixes: [Transcription.Fix]) -> String? {
        guard pastesSoFar < Settings.fixHintCount, skill == .notRequested, fixes.isEmpty,
              outcome == .cleaned || outcome == .skipped
        else { return nil }
        return hintSuffix
    }

    // MARK: - Word matching

    private static func stripPunctuation(_ word: String) -> String {
        var result = Substring(word)
        while let first = result.first, first.isPunctuation || first.isSymbol { result = result.dropFirst() }
        while let last = result.last, last.isPunctuation || last.isSymbol { result = result.dropLast() }
        return String(result)
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { stripPunctuation(String($0)).lowercased() }.filter { !$0.isEmpty }
    }

    private static func contains(_ words: [String], phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { start in
            Array(words[start..<(start + phrase.count)]) == phrase
        }
    }
}
