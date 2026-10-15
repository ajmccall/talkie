import Testing
@testable import Talkie

@Suite("TextRules")
struct TextRulesTests {
    @Test func collapsesRunsOfSpacesAndTrims() {
        #expect(TextRules.apply("  hello   world \n") == "hello world")
    }

    @Test func keepsSingleNewlines() {
        #expect(TextRules.apply("one\ntwo") == "one\ntwo")
    }
}

@Suite("Cleaner helpers")
struct CleanerHelperTests {
    @Test func stripsCompleteThinkBlock() {
        #expect(Cleaner.stripThinking("<think>reasoning</think>Hello.") == "Hello.")
    }

    @Test func stripsUnterminatedThinkBlock() {
        #expect(Cleaner.stripThinking("<think>still going") == "")
    }

    @Test func leavesTextWithoutThinkBlockAlone() {
        #expect(Cleaner.stripThinking("Plain text.") == "Plain text.")
    }

    @Test func instructionsUnchangedWithoutHint() {
        #expect(Cleaner.instructions(vocabularyHint: nil) == Cleaner.instructions)
    }

    @Test func instructionsInsertHintBeforeOutputRule() {
        let lines = Cleaner.instructions(vocabularyHint: "Spell it Alfie.").components(separatedBy: "\n")
        #expect(lines[lines.count - 2] == "- Spell it Alfie.")
        #expect(lines.last?.hasPrefix("- Output only") == true)
    }

    @Test func countsWords() {
        #expect(Cleaner.wordCount("  one two\nthree ") == 3)
        #expect(Cleaner.wordCount("") == 0)
    }

    @Test func acceptsLightEdits() {
        let raw = "um so I think we should uh meet on on Thursday"
        let cleaned = "So I think we should meet on Thursday."
        #expect(Cleaner.looksSane(raw: raw, cleaned: cleaned))
    }

    @Test func acceptsShortInputs() {
        #expect(Cleaner.looksSane(raw: "yes", cleaned: "Yes."))
        #expect(Cleaner.looksSane(raw: "ok", cleaned: "Okay, sounds good."))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!Cleaner.looksSane(raw: "something was said", cleaned: ""))
    }

    @Test func rejectsRunawayOutput() {
        let raw = "what is the capital of france"
        let answer = Array(repeating: "word", count: 40).joined(separator: " ")
        #expect(!Cleaner.looksSane(raw: raw, cleaned: answer))
    }

    @Test func rejectsHeavySummaries() {
        let raw = Array(repeating: "word", count: 30).joined(separator: " ")
        #expect(!Cleaner.looksSane(raw: raw, cleaned: "Summary."))
    }
}

@Suite("Timeout")
struct TimeoutTests {
    @Test func returnsResultWhenFast() async throws {
        let value = try await withTimeout(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test func throwsWhenSlow() async {
        await #expect(throws: TalkieError.timeout("Timed out after 0s")) {
            try await withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(5))
                return 0
            }
        }
    }
}

@Suite("Recording label")
struct RecordingLabelTests {
    @Test func formatsClock() {
        #expect(RecordingLabel.clock(0) == "0:00")
        #expect(RecordingLabel.clock(65) == "1:05")
        #expect(RecordingLabel.clock(299.9) == "4:59")
        #expect(RecordingLabel.clock(300) == "5:00")
    }

    @Test func plainUntilNearCap() {
        let early = RecordingLabel.label(elapsed: 83, cap: 300, warnBefore: 30)
        #expect(early == .init(text: "Listening…", nearCap: false))
        let justBefore = RecordingLabel.label(elapsed: 269.9, cap: 300, warnBefore: 30)
        #expect(!justBefore.nearCap)
    }

    @Test func countsDownNearCap() {
        let label = RecordingLabel.label(elapsed: 270, cap: 300, warnBefore: 30)
        #expect(label == .init(text: "Listening… 4:30 · stops at 5:00", nearCap: true))
    }

    @Test func clampsAtCap() {
        let label = RecordingLabel.label(elapsed: 305, cap: 300, warnBefore: 30)
        #expect(label.text == "Listening… 5:00 · stops at 5:00")
    }
}

@Suite("Cleanup outcome")
struct CleanupOutcomeTests {
    @Test func labelsRawFallbacks() {
        #expect(CleanupOutcome.cleaned.pastedLabel == "Pasted")
        #expect(CleanupOutcome.skipped.pastedLabel == "Pasted")
        #expect(CleanupOutcome.timedOut.pastedLabel == "Pasted (raw: cleanup timed out)")
        #expect(CleanupOutcome.rejected.pastedLabel == "Pasted (raw: cleanup rejected)")
        #expect(CleanupOutcome.failed.pastedLabel == "Pasted (raw: cleanup failed)")
    }

    @Test func fallbacksStayLonger() {
        #expect(CleanupOutcome.cleaned.hudSeconds == 1.5)
        #expect(CleanupOutcome.skipped.hudSeconds == 1.5)
        #expect(CleanupOutcome.timedOut.hudSeconds == 3)
        #expect(CleanupOutcome.rejected.hudSeconds == 3)
        #expect(CleanupOutcome.failed.hudSeconds == 3)
    }
}
