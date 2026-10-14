import AppKit
import os

/// Orchestrates: Fn down → record → Fn up → transcribe → clean → paste.
@MainActor
final class Controller {
    enum State {
        case loadingModels(String)
        case idle
        case recording
        case processing(String)
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?

    private let logger = Logger(subsystem: "talkie", category: "controller")
    private let fnKey = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let cleaner = Cleaner()
    private let hud = HUD()

    private var modelsReady = false
    private var isLoadingModels = false
    private var pressStartedAt: Date?
    private var lastLabel: RecordingLabel.Label?
    private var levelTimer: Timer?
    private var maxDurationTimer: Timer?
    private var accessibilityTimer: Timer?

    private(set) var state: State = .loadingModels("starting") {
        didSet { onStateChange?(state) }
    }

    func start() {
        fnKey.onPress = { [weak self] in self?.fnPressed() }
        fnKey.onRelease = { [weak self] in self?.fnReleased() }
        fnKey.start()

        Task { await requestPermissions() }
        Task { await loadModels() }
    }

    func stop() {
        fnKey.stop()
        levelTimer?.invalidate()
        maxDurationTimer?.invalidate()
        accessibilityTimer?.invalidate()
        if recorder.isRecording { _ = recorder.stop() }
    }

    /// Re-attempt model download/load, e.g. after a network failure.
    func reloadModels() {
        Task { await loadModels() }
    }

    // MARK: - Setup

    private func requestPermissions() async {
        let mic = await AudioRecorder.requestPermission()
        if !mic {
            logger.error("Microphone permission denied")
            hud.show(.init(kind: .failure, text: "Microphone access denied"), autoHideAfter: 4)
        }
        if Paster.isTrusted(prompt: true) {
            logger.info("Accessibility granted")
        } else {
            logger.notice("Accessibility not yet granted; Fn key and paste need it")
            watchForAccessibilityGrant()
        }
    }

    /// A global key monitor installed before Accessibility is granted stays
    /// deaf, so poll for the grant and reinstall it. Saves a relaunch.
    private func watchForAccessibilityGrant() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Paster.isTrusted(prompt: false) else { return }
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
                self.fnKey.restart()
                self.logger.info("Accessibility granted; Fn monitor restarted")
                self.hud.show(.init(kind: .success, text: "Accessibility granted"), autoHideAfter: 2)
            }
        }
    }

    private func loadModels() async {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        state = .loadingModels("starting")
        hud.show(.init(kind: .working, text: "Loading models…"))
        let progress: @Sendable (String) -> Void = { [weak self] detail in
            Task { @MainActor in
                self?.state = .loadingModels(detail)
                self?.hud.show(.init(kind: .working, text: detail))
            }
        }
        do {
            try await transcriber.load(progress: progress)
            try await cleaner.load(progress: progress)
            modelsReady = true
            state = .idle
            hud.show(.init(kind: .success, text: "Ready. Hold Fn to dictate."), autoHideAfter: 2.5)
        } catch {
            logger.error("Model load failed: \(error.localizedDescription)")
            state = .failed("Model load failed. Press Fn to retry.")
            hud.show(.init(kind: .failure, text: "Model load failed: \(error.localizedDescription)"), autoHideAfter: 6)
            Sounds.failed()
        }
    }

    // MARK: - Fn key

    private func fnPressed() {
        switch state {
        case .failed:
            reloadModels()
            return
        case .loadingModels:
            hud.show(.init(kind: .working, text: "Still loading models…"), autoHideAfter: 1.5)
            return
        case .processing:
            hud.show(.init(kind: .working, text: "Still working on the last one…"), autoHideAfter: 1.5)
            return
        case .recording:
            return
        case .idle:
            break
        }
        guard modelsReady else { return }

        do {
            try recorder.start()
        } catch {
            fail("Could not start recording: \(error.localizedDescription)")
            return
        }
        pressStartedAt = Date()
        state = .recording
        Sounds.recordingStarted()
        hud.show(.init(kind: .recording, text: "Listening…"))

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateRecordingLabel()
                self.hud.setLevel(self.recorder.level)
            }
        }
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Settings.maximumRecordingSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.logger.notice("Maximum recording length reached; stopping")
                self?.finishRecording(reason: .cap)
            }
        }
    }

    /// Switches the HUD to an amber countdown as the maximum length approaches.
    /// The text only changes once a second, so the HUD is re-laid-out rarely.
    private func updateRecordingLabel() {
        guard case .recording = state, let startedAt = pressStartedAt else { return }
        let label = RecordingLabel.label(elapsed: Date().timeIntervalSince(startedAt))
        guard label != lastLabel else { return }
        if label.nearCap, !(lastLabel?.nearCap ?? false) {
            Sounds.capApproaching()
        }
        lastLabel = label
        hud.show(.init(kind: label.nearCap ? .warning : .recording, text: label.text))
    }

    private func fnReleased() {
        finishRecording()
    }

    private enum StopReason { case released, cap }

    private func finishRecording(reason: StopReason = .released) {
        guard case .recording = state else { return }
        lastLabel = nil
        levelTimer?.invalidate()
        levelTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        let recording = recorder.stop()
        let held = Date().timeIntervalSince(pressStartedAt ?? Date())
        pressStartedAt = nil

        guard held >= Settings.minimumHoldSeconds, recording.duration >= Settings.minimumAudioSeconds else {
            logger.info("Ignoring short press (\(held, format: .fixed(precision: 2))s, \(recording.duration, format: .fixed(precision: 2))s audio)")
            state = .idle
            hud.hide()
            return
        }

        Sounds.recordingStopped()
        let message = reason == .cap ? "Max length reached, transcribing…" : "Transcribing…"
        state = .processing(message)
        hud.show(.init(kind: .working, text: message))
        Task { await process(recording) }
    }

    // MARK: - Pipeline

    private func process(_ recording: AudioRecorder.Recording) async {
        do {
            let raw = try await transcriber.transcribe(recording)
            logger.info("Raw: \(raw, privacy: .private)")
            guard !raw.isEmpty else {
                hud.show(.init(kind: .failure, text: "No speech detected"), autoHideAfter: 2)
                state = .idle
                return
            }

            var text = raw
            var outcome = CleanupOutcome.skipped
            if Settings.cleanupEnabled {
                state = .processing("Cleaning up…")
                hud.show(.init(kind: .working, text: "Cleaning up…"))
                (text, outcome) = await cleanedOrRaw(raw)
            }
            text = TextRules.apply(text)
            logger.info("Final: \(text, privacy: .private)")

            Paster.copy(text)
            try await Task.sleep(for: .milliseconds(Settings.pasteDelayMilliseconds))
            let pasted = Paster.pasteFromClipboard()
            Sounds.pasted()
            hud.show(
                .init(kind: .success, text: pasted ? outcome.pastedLabel : "Copied (grant Accessibility to paste)"),
                autoHideAfter: outcome.hudSeconds
            )
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Runs the LLM with a timeout and a sanity check; any problem falls back to the raw transcript.
    private func cleanedOrRaw(_ raw: String) async -> (text: String, outcome: CleanupOutcome) {
        let cleaner = self.cleaner
        do {
            let cleaned = try await withTimeout(seconds: Settings.cleanupTimeoutSeconds) {
                try await cleaner.clean(raw)
            }
            if Cleaner.looksSane(raw: raw, cleaned: cleaned) {
                return (cleaned, .cleaned)
            }
            logger.notice("Cleanup output rejected by sanity check; pasting raw transcript")
            return (raw, .rejected)
        } catch TalkieError.timeout {
            logger.error("Cleanup timed out after \(Int(Settings.cleanupTimeoutSeconds))s, pasting raw transcript")
            return (raw, .timedOut)
        } catch {
            logger.error("Cleanup failed, pasting raw transcript: \(error.localizedDescription)")
            return (raw, .failed)
        }
    }

    private func fail(_ message: String) {
        logger.error("\(message)")
        Sounds.failed()
        hud.show(.init(kind: .failure, text: message), autoHideAfter: 4)
        state = .idle
    }
}

/// How the cleanup step ended, so the paste message can say when raw text was used.
enum CleanupOutcome: Equatable {
    case cleaned, skipped, timedOut, rejected, failed

    var pastedLabel: String {
        switch self {
        case .cleaned, .skipped: return "Pasted"
        case .timedOut: return "Pasted (raw: cleanup timed out)"
        case .rejected: return "Pasted (raw: cleanup rejected)"
        case .failed: return "Pasted (raw: cleanup failed)"
        }
    }

    /// Raw fallbacks stay on screen longer so the reason can be read.
    var hudSeconds: TimeInterval {
        switch self {
        case .cleaned, .skipped: return 1.5
        case .timedOut, .rejected, .failed: return 3
        }
    }
}
