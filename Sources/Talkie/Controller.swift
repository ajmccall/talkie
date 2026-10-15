import AppKit
import os

/// Orchestrates: Fn down → record → Fn up → transcribe → clean → (skill) → paste.
/// Holding Shift during the dictation opens a picker the moment Fn is released;
/// the chosen skill runs on the cleaned text via the connected model account.
@MainActor
final class Controller {
    enum State {
        case loadingModels(String)
        case idle
        case recording
        case processing(String)
        case choosing
        case failed(String)
    }

    enum ConnectionState: Equatable {
        case notConfigured
        case checking
        case connected(ProviderAccount)
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?
    var onConnectionChange: ((ConnectionState) -> Void)?
    var onLastDictationChange: ((DictationRecord?) -> Void)?

    private let logger = Logger(subsystem: "talkie", category: "controller")
    private let fnKey = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let cleaner = Cleaner()
    private let hud = HUD()
    private let picker = SkillPicker()

    private var modelsReady = false
    private var isLoadingModels = false
    /// The download/session build started by the last vocabulary change, so a
    /// re-transcription can wait for it rather than run without the new term.
    private var vocabularyPreparation: Task<Void, Never>?
    private var pressStartedAt: Date?
    private var lastLabel: RecordingLabel.Label?
    private var levelTimer: Timer?
    private var maxDurationTimer: Timer?
    private var accessibilityTimer: Timer?
    private var provider: (any ModelProvider)?
    private var providerExecutable: URL?
    private var connectionTask: Task<Void, Never>?
    /// A CLI launched when Shift was first seen during a hold, waiting for its prompt.
    private var warmTransform: (any PreparedTransform)?

    private(set) var state: State = .loadingModels("starting") {
        didSet { onStateChange?(state) }
    }

    private(set) var connection: ConnectionState = .notConfigured {
        didSet { onConnectionChange?(connection) }
    }

    /// The most recent paste, kept in memory for Fix Last Dictation.
    private(set) var lastDictation: DictationRecord? {
        didSet { onLastDictationChange?(lastDictation) }
    }

    func start() {
        fnKey.onPress = { [weak self] in self?.fnPressed() }
        fnKey.onShiftSeen = { [weak self] in self?.prewarmProvider() }
        fnKey.onRelease = { [weak self] shift in self?.fnReleased(processorRequested: shift) }
        fnKey.start()

        Task { await requestPermissions() }
        Task { await loadModels() }
        if Settings.providerKind != nil { checkConnection() }
    }

    func stop() {
        fnKey.stop()
        levelTimer?.invalidate()
        maxDurationTimer?.invalidate()
        accessibilityTimer?.invalidate()
        if recorder.isRecording { _ = recorder.stop() }
        discardWarmTransform()
    }

    /// Re-attempt model download/load, e.g. after a network failure.
    func reloadModels() {
        Task { await loadModels() }
    }

    // MARK: - Model account

    func connect(kind: ProviderKind) {
        Settings.providerKind = kind
        checkConnection()
    }

    func disconnect() {
        connectionTask?.cancel()
        discardWarmTransform()
        Settings.providerKind = nil
        provider = nil
        providerExecutable = nil
        connection = .notConfigured
    }

    // MARK: - Pre-warmed CLI

    /// Shift seen while recording: a skill is likely, so start the CLI now and
    /// let its boot overlap the rest of the dictation. Nothing is sent yet.
    private func prewarmProvider() {
        guard case .recording = state, Settings.skillEnabled,
              let provider, let executable = providerExecutable else { return }
        discardWarmTransform()
        do {
            warmTransform = try provider.prepare(model: Settings.providerModel, executable: executable)
        } catch {
            logger.notice("Pre-warm failed, will launch on demand: \(error.localizedDescription)")
        }
    }

    /// Hands over the pre-warmed CLI if it is still alive and recent, else nil.
    private func takeWarmTransform() -> (any PreparedTransform)? {
        guard let warm = warmTransform else { return nil }
        warmTransform = nil
        let age = Date().timeIntervalSince(warm.startedAt)
        guard warm.isRunning, age < Settings.warmTransformMaximumAgeSeconds else {
            logger.notice("Pre-warmed CLI \(warm.isRunning ? "too old" : "exited") after \(age, format: .fixed(precision: 1))s; launching on demand")
            warm.discard()
            return nil
        }
        return warm
    }

    private func discardWarmTransform() {
        warmTransform?.discard()
        warmTransform = nil
    }

    /// Locates the CLI and asks it for its login state. Safe to call repeatedly.
    func checkConnection() {
        connectionTask?.cancel()
        guard let kind = Settings.providerKind, let provider = kind.makeProvider() else {
            connection = .notConfigured
            return
        }
        self.provider = provider
        connection = .checking
        connectionTask = Task { [weak self] in
            await self?.performConnectionCheck(provider)
        }
    }

    @discardableResult
    private func performConnectionCheck(_ provider: any ModelProvider) async -> Bool {
        do {
            let executable = try provider.locateExecutable(override: Settings.providerExecutableOverride(for: provider.kind))
            let account = try await provider.checkConnection(executable: executable)
            guard !Task.isCancelled else { return false }
            providerExecutable = executable
            connection = .connected(account)
            logger.info("\(provider.kind.displayName) connected (\(account.summary)) via \(executable.path)")
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            providerExecutable = nil
            let message = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            connection = .failed(message)
            logger.error("\(provider.kind.displayName) connection failed: \(message)")
            return false
        }
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
            await prepareVocabulary(progress: progress)
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

    // MARK: - Vocabulary

    /// The Vocabulary window saved a change: hand the list to Parakeet and fetch
    /// the extra model if this is the first term. Dictation keeps working either way.
    func vocabularyChanged() {
        guard modelsReady else { return }  // loadModels picks the list up itself
        let progress: @Sendable (String) -> Void = { [weak self] detail in
            Task { @MainActor in self?.hud.show(.init(kind: .working, text: detail)) }
        }
        let previous = vocabularyPreparation
        vocabularyPreparation = Task {
            await previous?.value
            await prepareVocabulary(progress: progress)
            if case .idle = state { hud.hide() }
        }
    }

    /// Re-runs Parakeet on a kept recording with the vocabulary now saved, so
    /// the Fix window can say whether the new spelling is picked up. Waits for
    /// any vocabulary download first; refuses while a dictation is in flight so
    /// the two never compete for the models.
    func retranscribe(_ record: DictationRecord, progress: @escaping @Sendable (String) -> Void) async throws -> Transcription {
        guard modelsReady else { throw TalkieError.notReady("Models are still loading; the word is saved for next time") }
        guard case .idle = state else { throw TalkieError.notReady("Talkie is busy, try again in a moment") }
        if let vocabularyPreparation {
            progress("preparing vocabulary")
            await vocabularyPreparation.value
        }
        progress("listening again")
        return try await transcriber.transcribe(record.recording)
    }

    /// Never throws: a failed download is reported, and the next dictation
    /// simply runs without the vocabulary pass.
    private func prepareVocabulary(progress: @escaping @Sendable (String) -> Void) async {
        let terms = Settings.vocabulary
        await transcriber.setVocabulary(terms)
        guard !terms.isEmpty else { return }
        do {
            try await transcriber.prepareVocabulary(progress: progress)
        } catch {
            logger.error("Vocabulary model failed: \(error.localizedDescription)")
            hud.show(.init(kind: .failure, text: "Vocabulary model failed: \(error.localizedDescription)"), autoHideAfter: 6)
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
        case .processing, .choosing:
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
                self?.finishRecording(reason: .cap, processorRequested: self?.fnKey.shiftSeen ?? false)
            }
        }
    }

    /// Switches the HUD to an amber countdown as the maximum length approaches.
    /// The text only changes once a second, so the HUD is re-laid-out rarely.
    private func updateRecordingLabel() {
        guard case .recording = state, let startedAt = pressStartedAt else { return }
        let skill = fnKey.shiftSeen && Settings.skillEnabled ? Settings.preselectedSkillPath.map(SkillPrompt.name(ofSkillAt:)) : nil
        let label = RecordingLabel.label(elapsed: Date().timeIntervalSince(startedAt), skill: skill)
        guard label != lastLabel else { return }
        if label.nearCap, !(lastLabel?.nearCap ?? false) {
            Sounds.capApproaching()
        }
        lastLabel = label
        hud.show(.init(kind: label.nearCap ? .warning : .recording, text: label.text))
    }

    private func fnReleased(processorRequested: Bool) {
        finishRecording(reason: .released, processorRequested: processorRequested)
    }

    private enum StopReason { case released, cap }

    private func finishRecording(reason: StopReason, processorRequested: Bool) {
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
            discardWarmTransform()
            state = .idle
            hud.hide()
            return
        }

        Sounds.recordingStopped()
        let message = reason == .cap ? "Max length reached, transcribing…" : "Transcribing…"
        state = .processing(message)

        // With a skill requested and available, the picker replaces the HUD right
        // away so the choice can be made while transcription runs.
        let skills = processorRequested && Settings.skillEnabled && provider != nil ? Settings.skillChoices : []
        var choice: Task<PickerResult, Never>?
        if !skills.isEmpty {
            hud.hide()
            let picker = self.picker
            let preselected = Settings.preselectedSkillPath
            choice = Task { await picker.present(skills: skills, preselected: preselected) }
            picker.setStatus(message, ready: false)
        } else {
            discardWarmTransform()
            hud.show(.init(kind: .working, text: message))
        }
        Task { await process(recording, processorRequested: processorRequested, choice: choice) }
    }

    /// Progress text goes to the picker while it is up, otherwise to the HUD.
    private func showProgress(_ text: String, pickerShown: Bool) {
        state = .processing(text)
        if pickerShown {
            picker.setStatus(text, ready: false)
        } else {
            hud.show(.init(kind: .working, text: text))
        }
    }

    // MARK: - Pipeline

    private func process(_ recording: AudioRecorder.Recording, processorRequested: Bool, choice: Task<PickerResult, Never>?) async {
        let pickerShown = choice != nil
        do {
            let transcription = try await transcriber.transcribe(recording)
            let raw = transcription.text
            let hint = Vocabulary.promptHint(Settings.vocabulary)
            logger.info("Raw: \(raw, privacy: .private)")
            guard !raw.isEmpty else {
                if pickerShown { picker.dismiss() }
                discardWarmTransform()
                hud.show(.init(kind: .failure, text: "No speech detected"), autoHideAfter: 2)
                state = .idle
                return
            }

            var text = raw
            var outcome = CleanupOutcome.skipped
            var skillOutcome = SkillOutcome.notRequested
            if let choice {
                // Skill path. Qwen3 only supplies the fallback text here, so it
                // runs alongside the skill rather than ahead of it, and the skill
                // starts on the highlighted entry before Enter is pressed.
                let input = TextRules.apply(raw)
                let cleanup = Task { () -> (String, CleanupOutcome) in
                    guard Settings.cleanupEnabled else { return (input, .skipped) }
                    let (cleaned, outcome) = await self.cleanedOrRaw(raw, hint: hint)
                    return (TextRules.apply(cleaned), outcome)
                }
                var inFlight = Settings.preselectedSkillPath.map { startSkill(input, skillPath: $0) }
                picker.setStatus("Ready", ready: true)
                state = .choosing
                let result = await choice.value
                picker.dismiss()
                switch result {
                case .asIs:
                    logger.info("Skill picker dismissed; pasting as-is")
                    inFlight?.task.cancel()
                    discardWarmTransform()
                    state = .processing("Pasting…")
                    (text, outcome) = await cleanup.value
                case .skill(let skill):
                    Settings.lastUsedSkillPath = skill.path
                    if inFlight?.path != skill.path {
                        inFlight?.task.cancel()
                        inFlight = startSkill(input, skillPath: skill.path)
                    }
                    let name = SkillPrompt.name(ofSkillAt: skill.path)
                    state = .processing("Applying \(name)…")
                    hud.show(.init(kind: .working, text: "Applying \(name)…"))
                    let applied: String?
                    (applied, skillOutcome) = await inFlight!.task.value
                    if let applied {
                        text = applied
                    } else {
                        (text, outcome) = await cleanup.value
                    }
                }
            } else {
                if Settings.cleanupEnabled {
                    showProgress("Cleaning up…", pickerShown: false)
                    (text, outcome) = await cleanedOrRaw(raw, hint: hint)
                }
                text = TextRules.apply(text)
            }
            if processorRequested, choice == nil {
                skillOutcome = Settings.providerKind == nil || provider == nil ? .notConnected : .noSkill
                logger.notice("Skill requested but unavailable: \(skillOutcome.pastedLabel ?? "")")
            }
            logger.info("Final: \(text, privacy: .private)")

            let fixHint = Correction.hudHint(pastesSoFar: Settings.fixHintsShown, outcome: outcome, skill: skillOutcome, fixes: transcription.fixes)
            if fixHint != nil { Settings.fixHintsShown += 1 }
            let label = (skillOutcome.pastedLabel ?? outcome.pastedLabel)
                + Vocabulary.fixedSuffix(transcription.fixes.map(\.term))
                + (fixHint ?? "")
            lastDictation = DictationRecord(recording: recording, raw: raw, fixes: transcription.fixes, text: text, outcome: label)

            Paster.copy(text)
            try await Task.sleep(for: .milliseconds(pickerShown ? Settings.pickerPasteDelayMilliseconds : Settings.pasteDelayMilliseconds))
            let pasted = Paster.pasteFromClipboard()
            Sounds.pasted()
            hud.show(
                .init(kind: .success, text: pasted ? label : "Copied (grant Accessibility to paste)"),
                autoHideAfter: fixHint != nil ? 3 : (skillOutcome.hudSeconds ?? outcome.hudSeconds)
            )
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Runs the LLM with a timeout and a sanity check; any problem falls back to the raw transcript.
    private func cleanedOrRaw(_ raw: String, hint: String?) async -> (text: String, outcome: CleanupOutcome) {
        let cleaner = self.cleaner
        do {
            let cleaned = try await withTimeout(seconds: Settings.cleanupTimeoutSeconds) {
                try await cleaner.clean(raw, vocabularyHint: hint)
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

    /// A skill run in progress. Cancelling the task terminates the CLI.
    private typealias SkillRun = (path: String, task: Task<(String?, SkillOutcome), Never>)

    /// Starts a skill on `text` straight away. The pre-warmed CLI, if any, is
    /// handed to the first run; a later run (the user changed their mind)
    /// launches on demand.
    private func startSkill(_ text: String, skillPath: String) -> SkillRun {
        let warm = takeWarmTransform()
        let task = Task { await self.applySkill(text, skillPath: skillPath, warm: warm) }
        return (skillPath, task)
    }

    /// Sends the text through the skill via the connected account, with a
    /// timeout. Returns the new text, or nil with the reason it was not applied.
    private func applySkill(_ text: String, skillPath: String, warm: (any PreparedTransform)?) async -> (String?, SkillOutcome) {
        guard let provider, Settings.providerKind != nil else {
            warm?.discard()
            logger.notice("Skill requested but no model account connected")
            return (nil, .notConnected)
        }
        let name = SkillPrompt.name(ofSkillAt: skillPath)

        if providerExecutable == nil {
            connectionTask?.cancel()
            connection = .checking
            _ = await performConnectionCheck(provider)
        }
        guard let executable = providerExecutable else {
            warm?.discard()
            let reason = (connection == .checking) ? "not connected" : shortFailure
            return (nil, .failed(name, reason))
        }

        let started = Date()
        do {
            let skill = try SkillPrompt.load(at: skillPath)
            let model = Settings.providerModel
            let applied = try await withTimeout(seconds: Settings.skillTimeoutSeconds) {
                if let warm { return try await warm.transform(text, skill: skill) }
                return try await provider.transform(text, skill: skill, model: model, executable: executable)
            }
            logger.info("Skill \(name) applied in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s\(warm == nil ? "" : " (pre-warmed)")")
            return (TextRules.apply(applied), .applied(name))
        } catch is CancellationError {
            logger.info("Skill \(name) cancelled")
            return (nil, .failed(name, "cancelled"))
        } catch TalkieError.timeout {
            logger.error("Skill \(name) timed out after \(Int(Settings.skillTimeoutSeconds))s, pasting cleaned text")
            return (nil, .timedOut(name))
        } catch let error as ProviderError {
            if case .signedOut = error { connection = .failed(error.errorDescription ?? "signed out") }
            logger.error("Skill \(name) failed, pasting cleaned text: \(error.localizedDescription)")
            return (nil, .failed(name, error.shortDescription))
        } catch {
            warm?.discard()
            logger.error("Skill \(name) failed, pasting cleaned text: \(error.localizedDescription)")
            return (nil, .failed(name, String(error.localizedDescription.prefix(40))))
        }
    }

    private var shortFailure: String {
        if case .failed(let message) = connection {
            let lower = message.lowercased()
            if lower.contains("signed out") { return "signed out" }
            if lower.contains("not found") { return "CLI not found" }
            if lower.contains("api key") { return "API key login" }
        }
        return "not connected"
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
