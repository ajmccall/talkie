import AVFoundation
import FluidAudio
import os

/// Local speech-to-text using NVIDIA Parakeet TDT (Core ML build from FluidAudio).
/// Models are downloaded once to ~/Library/Application Support/FluidAudio/Models.
actor Transcriber {
    private let logger = Logger(subsystem: "talkie", category: "asr")
    private var manager: AsrManager?
    private let converter = AudioConverter()

    static let modelVersion: AsrModelVersion = .v3

    var isLoaded: Bool { manager != nil }

    func load(progress: @escaping @Sendable (String) -> Void) async throws {
        guard manager == nil else { return }
        progress("downloading Parakeet")
        let models = try await AsrModels.downloadAndLoad(version: Self.modelVersion) { p in
            progress("Parakeet \(Int(p.fractionCompleted * 100))%")
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager

        // First inference compiles the Core ML graph; do it on silence so the
        // first real dictation is fast.
        progress("warming up Parakeet")
        var state = try TdtDecoderState()
        _ = try? await manager.transcribe([Float](repeating: 0, count: 16_000), decoderState: &state)
        logger.info("Parakeet ready")
    }

    func transcribe(_ recording: AudioRecorder.Recording) async throws -> String {
        guard let manager else { throw TalkieError.notReady("Parakeet not loaded") }
        let samples = try resample(recording)
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state, language: .english)
        logger.info("Transcribed \(recording.duration, format: .fixed(precision: 1))s in \(result.processingTime, format: .fixed(precision: 2))s")
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resample(_ recording: AudioRecorder.Recording) throws -> [Float] {
        if recording.sampleRate == 16_000 { return recording.samples }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: recording.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(recording.samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw TalkieError.audio("Could not build audio buffer") }
        recording.samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: src.count)
        }
        buffer.frameLength = AVAudioFrameCount(recording.samples.count)
        return try converter.resampleBuffer(buffer)
    }
}
