import AppKit
import Foundation
import Testing
@testable import Talkie

@Suite("ToneSynth")
struct ToneSynthTests {
    @Test func rendersNothingForNoNotes() {
        #expect(ToneSynth.render([]).isEmpty)
    }

    @Test func noteLastsUntilItHasDecayed() {
        let note = ToneSynth.Note(at: 0.1, hz: 440, decay: 0.2, amp: 0.3, timbre: .init(partials: [(1, 1)]))
        let samples = ToneSynth.render([note])
        #expect(samples.count == Int(note.end * ToneSynth.sampleRate))
        // Silent before the note, loudest soon after it starts, near-silent at the end.
        #expect(samples[Int(0.05 * ToneSynth.sampleRate)] == 0)
        let peak = samples.map(abs).max()!
        #expect(peak > 0.2 && peak <= 0.3)
        #expect(abs(samples.last!) < 0.002)
    }

    @Test func overlappingNotesStayWithinHeadroom() {
        let timbre = ToneSynth.Timbre(partials: [(1, 1), (2, 0.5)])
        let notes = (0..<6).map { _ in ToneSynth.Note(at: 0, hz: 440, decay: 0.1, amp: 0.9, timbre: timbre) }
        let peak = ToneSynth.render(notes).map(abs).max()!
        #expect(peak <= 0.9)
    }

    @Test func wavHeaderDescribesMono16BitPCM() {
        let data = ToneSynth.wav([0, 0.5, -0.5])
        #expect(data.count == 44 + 6)
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        #expect(data[22] == 1)  // channels
        #expect(data[34] == 16) // bits per sample
        #expect(String(data: data[36..<40], encoding: .ascii) == "data")
    }

    @Test func everySynthesisedThemeDefinesEveryCue() {
        for theme in SoundTheme.allCases where theme != .system && theme != .off {
            for cue in SoundCue.allCases {
                let samples = ToneSynth.render(theme.notes(for: cue))
                #expect(!samples.isEmpty, "\(theme) \(cue)")
                #expect(samples.map(abs).max()! <= 0.5, "\(theme) \(cue) too loud")
            }
        }
    }

    @Test func appKitAcceptsTheWav() {
        let samples = ToneSynth.render(SoundTheme.chime.notes(for: .pasted))
        let sound = NSSound(data: ToneSynth.wav(samples))
        #expect(sound != nil)
        #expect(abs((sound?.duration ?? 0) - Double(samples.count) / ToneSynth.sampleRate) < 0.01)
    }
}
