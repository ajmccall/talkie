import AppKit
import SwiftUI

/// Names and terms Parakeet should prefer, with their known mis-hearings.
/// Every add or remove is saved straight away and reported through `onChange`,
/// so a dictation made with the window still open uses the current list.
@MainActor
final class VocabularyWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let state = VocabularyState()

    /// Called after the saved list changed.
    var onChange: (() -> Void)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vocabulary"
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: VocabularyView(state: state, actions: .init(
            add: { [weak self] in self?.add() },
            remove: { [weak self] in self?.remove($0) },
            done: { [weak self] in self?.window.close() }
        )))
    }

    func show() {
        state.terms = Settings.vocabulary
        window.center()
        // Talkie is an accessory app; without activating, the window opens behind.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func add() {
        let text = state.newText
        let term = VocabularyTerm(text: text, aliases: Vocabulary.parseAliases(state.newAliases, excluding: text))
        let updated = Vocabulary.add(term, to: state.terms)
        guard updated != state.terms else { return }
        save(updated)
        state.newText = ""
        state.newAliases = ""
    }

    private func remove(_ term: VocabularyTerm) {
        save(Vocabulary.remove(id: term.id, from: state.terms))
    }

    private func save(_ terms: [VocabularyTerm]) {
        state.terms = terms
        Settings.vocabulary = terms
        onChange?()
    }
}

@MainActor
final class VocabularyState: ObservableObject {
    @Published var terms: [VocabularyTerm] = []
    @Published var newText = ""
    @Published var newAliases = ""
}

struct VocabularyActions {
    var add: () -> Void
    var remove: (VocabularyTerm) -> Void
    var done: () -> Void
}

struct VocabularyView: View {
    @ObservedObject var state: VocabularyState
    var actions: VocabularyActions

    private var problem: String? { Vocabulary.problem(with: state.newText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary").font(.title2).bold()
            Text("Names and unusual words Talkie should recognise. If it keeps hearing one wrong, add what it writes instead so it can match. Everyday words are best left out.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Word or name", text: $state.newText)
                        .textFieldStyle(.roundedBorder)
                    if let problem, !state.newText.isEmpty {
                        Text(problem).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Also heard as (comma separated)", text: $state.newAliases)
                    .textFieldStyle(.roundedBorder)
                Button("Add", action: actions.add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }

            List {
                if state.terms.isEmpty {
                    Text("No words yet. Try the name Talkie keeps getting wrong.")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.terms) { term in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.text).font(.body.weight(.medium))
                            Text(term.aliases.isEmpty ? "No known mis-hearings" : "Heard as " + term.aliases.joined(separator: ", "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { actions.remove(term) } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(term.text)")
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 200)

            HStack(alignment: .top) {
                Text("Talkie listens to the recording again for these, so a word is only swapped when it sounds right. The list is also shown to Qwen3.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done", action: actions.done).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
