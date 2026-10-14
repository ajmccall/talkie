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
