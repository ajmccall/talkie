import Foundation
import Testing
@testable import Talkie

@Suite("Vocabulary")
struct VocabularyTests {
    @Test func parsesAliasesTrimmedAndDeduped() {
        #expect(Vocabulary.parseAliases(" Alfy, alfi ,, ALFY , Alfie", excluding: "Alfie") == ["Alfy", "alfi"])
        #expect(Vocabulary.parseAliases("") == [])
    }

    @Test func addTrimsAndReplacesCaseInsensitively() {
        let list = Vocabulary.add(VocabularyTerm(text: " Alfie ", aliases: ["Alfy"]), to: [])
        #expect(list == [VocabularyTerm(text: "Alfie", aliases: ["Alfy"])])
        let updated = Vocabulary.add(VocabularyTerm(text: "alfie", aliases: ["Alfi", "alfie"]), to: list)
        #expect(updated == [VocabularyTerm(text: "alfie", aliases: ["Alfi"])])
    }

    @Test func addIgnoresInvalidTerms() {
        #expect(Vocabulary.add(VocabularyTerm(text: "Al"), to: []) == [])
        #expect(Vocabulary.add(VocabularyTerm(text: "  "), to: []) == [])
    }

    @Test func addAliasMergesIntoExistingTerm() {
        let list = [VocabularyTerm(text: "Alfie", aliases: ["Alfy"])]
        #expect(Vocabulary.addAlias("Alfi", to: "alfie", in: list) == [VocabularyTerm(text: "alfie", aliases: ["Alfy", "Alfi"])])
        #expect(Vocabulary.addAlias("Minderra", to: "Mindera", in: list) == list + [VocabularyTerm(text: "Mindera", aliases: ["Minderra"])])
        #expect(Vocabulary.addAlias("alfy", to: "Alfie", in: list) == list)
        #expect(Vocabulary.addAlias("Mindera", to: "Mindera", in: []) == [VocabularyTerm(text: "Mindera")])
        #expect(Vocabulary.addAlias("Aly", to: "Al", in: list) == list)
    }

    @Test func removesById() {
        let list = [VocabularyTerm(text: "Alfie"), VocabularyTerm(text: "Mindera")]
        #expect(Vocabulary.remove(id: "alfie", from: list) == [VocabularyTerm(text: "Mindera")])
    }

    @Test func reportsProblems() {
        #expect(Vocabulary.problem(with: "") != nil)
        #expect(Vocabulary.problem(with: "   ") != nil)
        #expect(Vocabulary.problem(with: "Al") != nil)
        #expect(Vocabulary.problem(with: "Alfie") == nil)
    }

    @Test func promptHintListsTermsAndAliases() {
        #expect(Vocabulary.promptHint([]) == nil)
        let hint = Vocabulary.promptHint([
            VocabularyTerm(text: "Alfie", aliases: ["Alfy"]),
            VocabularyTerm(text: "Mindera"),
        ])!
        #expect(hint.contains("Alfie (often mis-heard as Alfy); Mindera."))
        #expect(hint.contains("do not insert them"))
    }

    @Test func promptHintIsCapped() {
        let terms = (0..<(Vocabulary.maximumPromptTerms + 5)).map { VocabularyTerm(text: "Term\($0)") }
        let hint = Vocabulary.promptHint(terms)!
        #expect(hint.contains("Term\(Vocabulary.maximumPromptTerms - 1)"))
        #expect(!hint.contains("Term\(Vocabulary.maximumPromptTerms)"))
    }

    @Test func fixedSuffixShapes() {
        #expect(Vocabulary.fixedSuffix([]) == "")
        #expect(Vocabulary.fixedSuffix(["Alfie", "Alfie"]) == " (fixed Alfie)")
        #expect(Vocabulary.fixedSuffix(["Alfie", "Mindera"]) == " (fixed Alfie, Mindera)")
        #expect(Vocabulary.fixedSuffix(["A1", "B2", "C3"]) == " (fixed 3 terms)")
    }

    @Test func appliesFixesKeepingPunctuation() {
        let fixes = [
            Transcription.Fix(original: "Ratminds.", term: "Rathmines"),
            Transcription.Fix(original: "Quen,", term: "Qwen"),
            Transcription.Fix(original: "Minderra", term: "Mindera"),
        ]
        let text = "At Minderra we tested Quen, then Quench at Ratminds."
        #expect(Vocabulary.applyFixes(fixes, to: text) == "At Mindera we tested Qwen, then Quench at Rathmines.")
    }

    @Test func applyFixesFailsWhenAWordIsMissing() {
        let fixes = [Transcription.Fix(original: "Quen", term: "Qwen")]
        #expect(Vocabulary.applyFixes(fixes, to: "only Quench here") == nil)
        #expect(Vocabulary.applyFixes([], to: "unchanged") == "unchanged")
    }

    @Test func storageRoundTrips() {
        let list = [VocabularyTerm(text: "Alfie", aliases: ["Alfy"])]
        #expect(Vocabulary.decode(Vocabulary.encode(list)) == list)
        #expect(Vocabulary.decode(nil) == [])
        #expect(Vocabulary.decode(Data("nonsense".utf8)) == [])
    }

    @Test func parsesListFormat() {
        let list = Vocabulary.parse(list: """
            # names
            Alfie: Alfy, Alfi

            Mindera
            al
            """)
        #expect(list == [
            VocabularyTerm(text: "Alfie", aliases: ["Alfy", "Alfi"]),
            VocabularyTerm(text: "Mindera"),
        ])
    }
}
