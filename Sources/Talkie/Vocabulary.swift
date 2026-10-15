import Foundation

/// A name or term Parakeet should prefer, with the spellings it is known to
/// produce instead ("Alfie", heard as "Alfy"). The canonical text is what ends
/// up in the transcript.
struct VocabularyTerm: Codable, Equatable, Hashable, Identifiable, Sendable {
    var text: String
    var aliases: [String] = []

    var id: String { text.lowercased() }
}

/// Pure helpers for the vocabulary list: validation, editing, storage and the
/// hint line handed to Qwen3. The acoustic matching itself is in Transcriber.
enum Vocabulary {
    /// FluidAudio's rescorer skips terms shorter than this outright.
    static let minimumLength = 3

    /// The Qwen3 hint stays short; the acoustic pass has no such cap.
    static let maximumPromptTerms = 60

    /// "Alfy, alfi ,, " -> ["Alfy", "alfi"]: trimmed, no empties, no
    /// case-insensitive duplicates, and never the term itself.
    static func parseAliases(_ field: String, excluding term: String = "") -> [String] {
        var seen: Set<String> = [term.lowercased()]
        var result: [String] = []
        for piece in field.split(separator: ",") {
            let alias = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, seen.insert(alias.lowercased()).inserted else { continue }
            result.append(alias)
        }
        return result
    }

    /// Trims the term; a term already in the list (ignoring case) is replaced
    /// in place rather than duplicated.
    static func add(_ term: VocabularyTerm, to list: [VocabularyTerm]) -> [VocabularyTerm] {
        let text = term.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard problem(with: text) == nil else { return list }
        let cleaned = VocabularyTerm(text: text, aliases: parseAliases(term.aliases.joined(separator: ","), excluding: text))
        var result = list
        if let index = result.firstIndex(where: { $0.id == cleaned.id }) {
            result[index] = cleaned
        } else {
            result.append(cleaned)
        }
        return result
    }

    /// Adds `alias` to the term with that text (ignoring case), creating the
    /// term when it is missing. The list comes back unchanged when the alias is
    /// already known, equals the term, or the term is invalid.
    static func addAlias(_ alias: String, to termText: String, in list: [VocabularyTerm]) -> [VocabularyTerm] {
        let id = termText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = list.first { $0.id == id }
        return add(VocabularyTerm(text: termText, aliases: (existing?.aliases ?? []) + [alias]), to: list)
    }

    static func remove(id: String, from list: [VocabularyTerm]) -> [VocabularyTerm] {
        list.filter { $0.id != id }
    }

    /// Why a term cannot be added, or nil when it can.
    static func problem(with text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Type a word or name" }
        if trimmed.count < minimumLength { return "Too short to match (\(minimumLength)+ letters)" }
        return nil
    }

    /// One line for the cleanup prompt, or nil when there is nothing to say.
    static func promptHint(_ terms: [VocabularyTerm]) -> String? {
        guard !terms.isEmpty else { return nil }
        let listed = terms.prefix(maximumPromptTerms).map { term -> String in
            term.aliases.isEmpty ? term.text : "\(term.text) (often mis-heard as \(term.aliases.joined(separator: ", ")))"
        }
        return "The speaker often uses these names and terms; spell them exactly like this: "
            + listed.joined(separator: "; ")
            + ". Keep these spellings where they occur; do not insert them where nothing similar was said."
    }

    /// Appended to the paste message: " (fixed Alfie)", " (fixed Alfie, Mindera)", " (fixed 3 terms)".
    static func fixedSuffix(_ terms: [String]) -> String {
        var unique: [String] = []
        for term in terms where !unique.contains(term) { unique.append(term) }
        switch unique.count {
        case 0: return ""
        case 1, 2: return " (fixed \(unique.joined(separator: ", ")))"
        default: return " (fixed \(unique.count) terms)"
        }
    }

    /// Applies the rescorer's replacements to the original transcript rather
    /// than taking its rebuilt text, so punctuation attached to a replaced word
    /// ("Ratminds." → "Rathmines.") survives. Nil when a word cannot be placed,
    /// in which case the caller falls back to the rebuilt text.
    static func applyFixes(_ fixes: [Transcription.Fix], to text: String) -> String? {
        var result = text
        for fix in fixes {
            guard let range = wholeWordRange(of: fix.original, in: result) else { return nil }
            let trailing = trailingPunctuation(of: fix.original)
            let replacement = fix.term + (fix.term.hasSuffix(trailing) ? "" : trailing)
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func wholeWordRange(of word: String, in text: String) -> Range<String.Index>? {
        guard !word.isEmpty else { return nil }
        var from = text.startIndex
        while from < text.endIndex, let range = text.range(of: word, range: from..<text.endIndex) {
            let startsWord = range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)] == " "
            let endsWord = range.upperBound == text.endIndex || text[range.upperBound] == " "
            if startsWord && endsWord { return range }
            from = range.upperBound
        }
        return nil
    }

    private static func trailingPunctuation(of word: String) -> String {
        String(word.reversed().prefix { $0.isPunctuation }.reversed())
    }

    // MARK: - Storage

    static func decode(_ data: Data?) -> [VocabularyTerm] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([VocabularyTerm].self, from: data)) ?? []
    }

    static func encode(_ terms: [VocabularyTerm]) -> Data {
        (try? JSONEncoder().encode(terms)) ?? Data()
    }

    /// One term per line, optionally "Alfie: Alfy, Alfi". Blank lines and
    /// lines starting with # are skipped. Used by `--selftest --vocab`.
    static func parse(list: String) -> [VocabularyTerm] {
        var result: [VocabularyTerm] = []
        for line in list.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            let text = parts[0].trimmingCharacters(in: .whitespaces)
            let aliases = parts.count > 1 ? parseAliases(parts[1], excluding: text) : []
            result = add(VocabularyTerm(text: text, aliases: aliases), to: result)
        }
        return result
    }
}
