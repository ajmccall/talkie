import AVFoundation
import Foundation

/// `Talkie --selftest <audio file>` runs the transcribe → clean pipeline on a
/// file and prints the result, without starting the menu-bar app. Useful for
/// checking models and tuning the cleanup prompt.
enum SelfTest {
    static func run(path: String) async -> Int32 {
        do {
            let recording = try load(path: path)
            print("Audio: \(String(format: "%.1f", recording.duration))s at \(Int(recording.sampleRate)) Hz")

            let transcriber = Transcriber()
            try await transcriber.load { print("  asr: \($0)") }
            var started = Date()
            let raw = try await transcriber.transcribe(recording)
            print("Raw (\(String(format: "%.2f", Date().timeIntervalSince(started)))s):\n  \(raw)")

            let cleaner = Cleaner()
            try await cleaner.load { print("  llm: \($0)") }
            started = Date()
            let cleaned = TextRules.apply(try await cleaner.clean(raw))
            print("Cleaned (\(String(format: "%.2f", Date().timeIntervalSince(started)))s):\n  \(cleaned)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("selftest failed: \(error)\n".utf8))
            return 1
        }
    }

    private static func load(path: String) throws -> AudioRecorder.Recording {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TalkieError.audio("Could not allocate buffer")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw TalkieError.audio("Not float PCM") }
        let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
        return AudioRecorder.Recording(samples: samples, sampleRate: format.sampleRate)
    }
}
