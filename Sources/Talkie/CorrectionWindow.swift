import AppKit
import SwiftUI

/// Shows the last dictation as clickable words so a mis-heard name can be
/// added to the vocabulary, then listens to the same recording again and says
/// whether the new spelling is picked up. The vocabulary is saved straight
/// away and reported through `onChange`, like the Vocabulary window.
@MainActor
final class CorrectionWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let state = CorrectionState()

    /// Called after the saved vocabulary changed.
    var onChange: (() -> Void)?
    /// Re-transcribes a kept recording with the vocabulary as saved now.
    var verify: ((DictationRecord, @escaping @Sendable (String) -> Void) async throws -> Transcription)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fix Last Dictation"
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: CorrectionView(state: state, actions: .init(
            toggle: { [weak self] in self?.toggle($0) },
            add: { [weak self] in self?.add() },
            showNewer: { [weak self] in self?.showNewer() },
            done: { [weak self] in self?.window.close() }
        )))
    }

    func show(_ record: DictationRecord) {
        load(record)
        window.center()
        // Talkie is an accessory app; without activating, the window opens behind.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A dictation landed while the window is open: offer it rather than
    /// replacing what the user is looking at.
    func lastDictationChanged(_ record: DictationRecord?) {
        guard window.isVisible, let record, record.id != state.record?.id else { return }
        state.newer = record
    }

    private func load(_ record: DictationRecord) {
        state.record = record
        state.chips = Correction.chips(record.raw)
        state.selection = nil
        state.heard = ""
        state.shouldBe = ""
        state.phase = .editing
        state.newer = nil
    }

    private func showNewer() {
        if let newer = state.newer { load(newer) }
    }

    private func toggle(_ index: Int) {
        state.selection = Correction.toggle(index, in: state.selection)
        state.heard = Correction.heard(state.selection, in: state.chips) ?? ""
        state.phase = .editing
    }

    private func add() {
        guard let record = state.record, let verify else { return }
        let term = state.shouldBe.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = state.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = Settings.vocabulary
        let updated = Vocabulary.addAlias(alias, to: term, in: current)
        let saved = updated != current
        if saved {
            Settings.vocabulary = updated
            onChange?()
        }
        state.phase = .checking("Checking against the recording…")
        Task { [weak self] in
            do {
                let after = try await verify(record) { detail in
                    Task { @MainActor in self?.state.phase = .checking(detail.prefix(1).uppercased() + detail.dropFirst() + "…") }
                }
                self?.state.phase = .verdict(Correction.verdict(term: term, alias: alias, after: after), saved: saved)
            } catch {
                self?.state.phase = .failed(error.localizedDescription)
            }
        }
    }
}

@MainActor
final class CorrectionState: ObservableObject {
    enum Phase: Equatable {
        case editing
        case checking(String)
        case verdict(Correction.Verdict, saved: Bool)
        case failed(String)
    }

    @Published var record: DictationRecord?
    @Published var chips: [Correction.Chip] = []
    @Published var selection: ClosedRange<Int>?
    /// Filled from the selection; still editable.
    @Published var heard = ""
    @Published var shouldBe = ""
    @Published var phase: Phase = .editing
    @Published var newer: DictationRecord?
}

struct CorrectionActions {
    var toggle: (Int) -> Void
    var add: () -> Void
    var showNewer: () -> Void
    var done: () -> Void
}

struct CorrectionView: View {
    @ObservedObject var state: CorrectionState
    var actions: CorrectionActions
    @FocusState private var shouldBeFocused: Bool

    private var problem: String? { Vocabulary.problem(with: state.shouldBe) }
    private var checking: Bool {
        if case .checking = state.phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fix Last Dictation").font(.title2).bold()
            Text("Click the word Talkie got wrong (two adjacent words for a longer name), type what it should have been, and Talkie adds it to the Vocabulary and listens to this recording again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let record = state.record {
                Text("\(record.date, format: .relative(presentation: .named)) · \(record.outcome)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(state.chips) { chip in
                            ChipButton(chip: chip, selected: state.selection?.contains(chip.id) == true) {
                                actions.toggle(chip.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60, maxHeight: 150)

                if record.text != record.raw {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pasted as").font(.caption).foregroundStyle(.secondary)
                        Text(record.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Grid(alignment: .leading, verticalSpacing: 8) {
                GridRow {
                    Text("Heard as")
                    TextField("Click a word above", text: $state.heard)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Should be")
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("The right spelling", text: $state.shouldBe)
                            .textFieldStyle(.roundedBorder)
                            .focused($shouldBeFocused)
                        if let problem, !state.shouldBe.isEmpty {
                            Text(problem).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                result
                Spacer()
                Button("Add and check", action: actions.add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || checking)
            }

            HStack(alignment: .top) {
                if state.newer != nil {
                    Button("Newer dictation available – Show", action: actions.showNewer)
                        .buttonStyle(.link)
                } else {
                    Text("Kept in memory until the next dictation or Talkie quits.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Done", action: actions.done).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: state.selection) { _, selection in
            if selection != nil { shouldBeFocused = true }
        }
    }

    @ViewBuilder
    private var result: some View {
        switch state.phase {
        case .editing:
            EmptyView()
        case .checking(let text):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        case .verdict(let verdict, let saved):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: verdict.isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(verdict.isGood ? Color.green : Color.orange)
                Text(saved ? verdict.message : "Already listed. " + verdict.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Check again", action: actions.add)
            }
        }
    }
}

private struct ChipButton: View {
    let chip: Correction.Chip
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(chip.display)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.08), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(selected ? "Click to deselect" : "Mark “\(chip.word)” as mis-heard")
    }
}
