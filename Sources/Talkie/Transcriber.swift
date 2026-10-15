import AVFoundation
import FluidAudio
import os

/// What came out of the speech models for one recording.
struct Transcription: Sendable {
    struct Fix: Sendable, Equatable {
        let original: String
        let term: String
    }

    let text: String
    /// Vocabulary terms swapped in by the acoustic pass, in order of appearance.
    let fixes: [Fix]
}

/// Local speech-to-text using NVIDIA Parakeet TDT (Core ML build from FluidAudio).
/// Models are downloaded once to ~/Library/Application Support/FluidAudio/Models.
///
/// With a vocabulary set, a second small Parakeet CTC model re-checks the audio
/// for each term and swaps a word only when the sound supports it. The term
/// list can change at any time; the session is rebuilt lazily.
actor Transcriber {
    private let logger = Logger(subsystem: "talkie", category: "asr")
    private var manager: AsrManager?
    private let converter = AudioConverter()

    private var vocabulary: [VocabularyTerm] = []
    private var ctcModels: CtcModels?
    private var session: VocabularyBoostingSession?
    private var sessionTerms: [VocabularyTerm] = []
    /// Set when building the session failed, so a dictation does not retry a
    /// download; cleared by the next vocabulary change.
    private var sessionBuildFailed = false

    static let modelVersion: AsrModelVersion = .v3
    static let ctcVariant: CtcModelVariant = .ctc110m

    var isLoaded: Bool { manager != nil }

    /// The vocabulary model is already on disk, so preparing it is quick.
    static var vocabularyModelDownloaded: Bool {
        CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory(for: ctcVariant))
    }

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

    // MARK: - Vocabulary

    func setVocabulary(_ terms: [VocabularyTerm]) {
        vocabulary = terms
        sessionBuildFailed = false
        if terms != sessionTerms { session = nil }
    }

    /// Downloads the CTC model if needed and builds the matching session, so the
    /// next dictation pays nothing extra. No-op with an empty vocabulary.
    func prepareVocabulary(progress: @escaping @Sendable (String) -> Void) async throws {
        guard !vocabulary.isEmpty else { return }
        if ctcModels == nil {
            progress(Self.vocabularyModelDownloaded ? "loading vocabulary model" : "downloading vocabulary model (about 100 MB)")
            ctcModels = try await CtcModels.downloadAndLoad(variant: Self.ctcVariant)
            logger.info("Vocabulary model ready")
        }
        if session == nil || sessionTerms != vocabulary {
            progress("preparing vocabulary")
            try await buildSession()
        }
    }

    private func buildSession() async throws {
        guard let ctcModels else { throw TalkieError.notReady("Vocabulary model not loaded") }
        let terms = vocabulary.map {
            CustomVocabularyTerm(text: $0.text, aliases: $0.aliases.isEmpty ? nil : $0.aliases)
        }
        // The spotter-anchored "rescue" proposes a term wherever the CTC model
        // hears something like it, regardless of what Parakeet wrote. With a
        // short list of names it replaced ordinary phrases ("it seems", "Unix
        // command" → "Mindera"); without it, false swaps on a minute of plain
        // speech dropped to zero and recall on real mishearings was unchanged.
        session = try await VocabularyBoostingSession(
            vocabulary: CustomVocabularyContext(terms: terms),
            ctcModels: ctcModels,
            config: VocabularyRescorer.Config(spotterRescueEnabled: false)
        )
        sessionTerms = vocabulary
        logger.info("Vocabulary session built with \(terms.count) term(s)")
    }

    /// The session for the current vocabulary, or nil when there is none to
    /// apply or it cannot be built. A missing CTC model is not downloaded here:
    /// that happens in `prepareVocabulary`, off the dictation path.
    private func currentSession() async -> VocabularyBoostingSession? {
        guard !vocabulary.isEmpty, ctcModels != nil, !sessionBuildFailed else { return nil }
        if let session, sessionTerms == vocabulary { return session }
        do {
            try await buildSession()
            return session
        } catch {
            sessionBuildFailed = true
            logger.error("Vocabulary session failed, transcribing without it: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Transcription

    func transcribe(_ recording: AudioRecorder.Recording) async throws -> Transcription {
        guard let manager else { throw TalkieError.notReady("Parakeet not loaded") }
        let samples = try resample(recording)
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state, language: .english)
        logger.info("Transcribed \(recording.duration, format: .fixed(precision: 1))s in \(result.processingTime, format: .fixed(precision: 2))s")

        var text = result.text
        var fixes: [Transcription.Fix] = []
        if let session = await currentSession() {
            let started = Date()
            let output = await session.rescore(text: text, tokenTimings: result.tokenTimings ?? [], audioSamples: samples)
            let elapsed = Date().timeIntervalSince(started)
            if let output, output.wasModified {
                fixes = output.replacements.compactMap { replacement in
                    guard replacement.shouldReplace, let term = replacement.replacementWord else { return nil }
                    return Transcription.Fix(original: replacement.originalWord, term: term)
                }
                // The rescorer's own text loses punctuation attached to a replaced word.
                text = Vocabulary.applyFixes(fixes, to: text) ?? output.text
                for fix in fixes {
                    logger.info("Vocabulary fixed '\(fix.original, privacy: .public)' → '\(fix.term, privacy: .public)'")
                }
            }
            logger.info("Vocabulary pass \(elapsed, format: .fixed(precision: 2))s, \(fixes.count) fix(es), heard: \(output?.detectedTerms.joined(separator: ", ") ?? "none", privacy: .public)")
        }
        return Transcription(text: text.trimmingCharacters(in: .whitespacesAndNewlines), fixes: fixes)
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
