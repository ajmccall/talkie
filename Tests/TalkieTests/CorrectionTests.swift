import Foundation
import Testing
@testable import Talkie

@Suite("Correction")
struct CorrectionTests {
    @Test func chipsKeepPunctuationOnDisplayOnly() {
        let chips = Correction.chips("At Minderra we tested Quen, then “Ratminds.”")
        #expect(chips.map(\.display) == ["At", "Minderra", "we", "tested", "Quen,", "then", "“Ratminds.”"])
        #expect(chips.map(\.word) == ["At", "Minderra", "we", "tested", "Quen", "then", "Ratminds"])
        #expect(chips.map(\.id) == Array(0..<7))
        #expect(Correction.chips("don't").first?.word == "don't")
        #expect(Correction.chips("").isEmpty)
    }

    @Test func toggleBuildsContiguousSelection() {
        var selection = Correction.toggle(2, in: nil)
        #expect(selection == 2...2)
        selection = Correction.toggle(3, in: selection)
        #expect(selection == 2...3)
        selection = Correction.toggle(1, in: selection)
        #expect(selection == 1...3)
        selection = Correction.toggle(3, in: selection)
        #expect(selection == 1...2)
        selection = Correction.toggle(5, in: selection)
        #expect(selection == 5...5)
        selection = Correction.toggle(5, in: selection)
        #expect(selection == nil)
        // A click inside a longer range starts over there.
        #expect(Correction.toggle(2, in: 0...4) == 2...2)
    }

    @Test func heardJoinsAdjacentChips() {
        let chips = Correction.chips("the Rath mines, road")
        #expect(Correction.heard(1...2, in: chips) == "Rath mines")
        #expect(Correction.heard(nil, in: chips) == nil)
        #expect(Correction.heard(1...1, in: chips) == "Rath")
    }

    @Test func verdictFixed() {
        let after = Transcription(text: "Ask Alfie to send it.", fixes: [.init(original: "alfy", term: "Alfie")])
        #expect(Correction.verdict(term: "Alfie", alias: "Alfy", after: after) == .fixed(term: "Alfie"))
        #expect(Correction.verdict(term: "Alfie", alias: "Alfy", after: after).isGood)
    }

    @Test func verdictAlreadyCorrectIgnoresCaseAndPunctuation() {
        let after = Transcription(text: "We met at Rathmines.", fixes: [])
        #expect(Correction.verdict(term: "rathmines", alias: "Ratminds", after: after) == .alreadyCorrect(term: "rathmines"))
        #expect(Correction.verdict(term: "Rath mines", alias: "x", after: after) == .stillWrong(term: "Rath mines", heard: nil))
    }

    @Test func verdictStillWrongReportsTheAliasWhenStillThere() {
        let after = Transcription(text: "Ask Alfy to send it.", fixes: [])
        #expect(Correction.verdict(term: "Alfie", alias: "Alfy", after: after) == .stillWrong(term: "Alfie", heard: "Alfy"))
        #expect(Correction.verdict(term: "Alfie", alias: "Alfi", after: after) == .stillWrong(term: "Alfie", heard: nil))
        #expect(!Correction.verdict(term: "Alfie", alias: "Alfy", after: after).isGood)
        #expect(Correction.Verdict.stillWrong(term: "Alfie", heard: "Alfy").message.contains("Alfy"))
    }

    @Test func hudHintOnlyForFirstPlainPastes() {
        #expect(Correction.hudHint(pastesSoFar: 0, outcome: .cleaned, skill: .notRequested, fixes: []) == Correction.hintSuffix)
        #expect(Correction.hudHint(pastesSoFar: Settings.fixHintCount - 1, outcome: .skipped, skill: .notRequested, fixes: []) != nil)
        #expect(Correction.hudHint(pastesSoFar: Settings.fixHintCount, outcome: .cleaned, skill: .notRequested, fixes: []) == nil)
        #expect(Correction.hudHint(pastesSoFar: 0, outcome: .timedOut, skill: .notRequested, fixes: []) == nil)
        #expect(Correction.hudHint(pastesSoFar: 0, outcome: .cleaned, skill: .applied("Email"), fixes: []) == nil)
        #expect(Correction.hudHint(pastesSoFar: 0, outcome: .cleaned, skill: .notRequested, fixes: [.init(original: "Alfy", term: "Alfie")]) == nil)
    }
}
