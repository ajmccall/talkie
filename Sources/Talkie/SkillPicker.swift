import AppKit
import SwiftUI

/// One entry in the picker: a SKILL.md path and its display name.
struct SkillChoice: Equatable, Identifiable, Sendable {
    let path: String
    let name: String
    var id: String { path }
}

enum PickerResult: Equatable, Sendable {
    case skill(SkillChoice)
    case asIs
}

// MARK: - Pure helpers (unit tested)

/// The user's list of skills, in the order they were added.
enum SkillList {
    /// Seeds an empty list from the single-skill setting of earlier versions.
    static func migrate(legacy: String?, existing: [String]) -> [String] {
        guard existing.isEmpty, let legacy, !legacy.isEmpty else { return existing }
        return [legacy]
    }

    static func add(_ paths: [String], to list: [String]) -> [String] {
        var result = list
        for path in paths where !result.contains(path) { result.append(path) }
        return result
    }

    static func remove(_ path: String, from list: [String]) -> [String] {
        list.filter { $0 != path }
    }

    /// The entry highlighted when the picker opens: the last one used if it is
    /// still in the list, else the first.
    static func preselected(paths: [String], lastUsed: String?) -> String? {
        if let lastUsed, paths.contains(lastUsed) { return lastUsed }
        return paths.first
    }
}

enum PickerNavigation {
    enum Direction { case up, down }

    /// Arrow keys wrap around the ends.
    static func move(_ direction: Direction, from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        switch direction {
        case .up: return (index - 1 + count) % count
        case .down: return (index + 1) % count
        }
    }

    /// Number keys 1–9 pick a row directly.
    static func index(forNumberKey number: Int, count: Int) -> Int? {
        guard number >= 1, number <= 9, number <= count else { return nil }
        return number - 1
    }
}

// MARK: - Picker

@MainActor
final class SkillPickerState: ObservableObject {
    @Published var skills: [SkillChoice] = []
    @Published var selectedIndex = 0
    @Published var status = ""
    @Published var ready = false
}

/// A borderless panel that takes keyboard focus without activating Talkie, so
/// the app you dictated into stays frontmost and receives the paste afterwards.
private final class KeyablePanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }

    /// Escape arrives here when nothing else handles it.
    override func cancelOperation(_ sender: Any?) {
        _ = onKeyDown?(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: windowNumber, context: nil, characters: "\u{1B}",
                                         charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!)
    }
}

/// The skill picker: same floating pill as the HUD, with a list. Shown the
/// moment Fn is released so the choice can be made while transcription runs.
@MainActor
final class SkillPicker: NSObject, NSWindowDelegate {
    private let panel: KeyablePanel
    private let state = SkillPickerState()
    private var continuation: CheckedContinuation<PickerResult, Never>?

    override init() {
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        super.init()
        panel.delegate = self
        panel.onKeyDown = { [weak self] event in self?.handle(event) ?? false }
        panel.contentView = NSHostingView(rootView: SkillPickerView(state: state) { [weak self] index in
            self?.choose(index)
        })
    }

    var isPresented: Bool { continuation != nil }

    /// Shows the list and waits for Return, Escape, a click, a number key, or
    /// the panel losing focus (treated as Escape).
    func present(skills: [SkillChoice], preselected: String?) async -> PickerResult {
        resolve(.asIs)  // a stale presentation, if any, pastes as-is
        state.skills = skills
        state.selectedIndex = skills.firstIndex { $0.path == preselected } ?? 0
        state.status = "Transcribing…"
        state.ready = false
        PanelPlacement.bottomCentre(panel)
        panel.makeKeyAndOrderFront(nil)
        return await withCheckedContinuation { continuation = $0 }
    }

    func setStatus(_ text: String, ready: Bool) {
        state.status = text
        state.ready = ready
        PanelPlacement.bottomCentre(panel)
    }

    /// Hides the panel. A choice still pending resolves as "paste as-is".
    func dismiss() {
        resolve(.asIs)
        panel.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard continuation != nil else { return }
        resolve(.asIs)
        panel.orderOut(nil)
    }

    // MARK: Input

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: state.selectedIndex = PickerNavigation.move(.up, from: state.selectedIndex, count: state.skills.count); return true
        case 125: state.selectedIndex = PickerNavigation.move(.down, from: state.selectedIndex, count: state.skills.count); return true
        case 36, 76: choose(state.selectedIndex); return true
        case 53: resolve(.asIs); return true
        default: break
        }
        if let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
           let index = PickerNavigation.index(forNumberKey: digit, count: state.skills.count) {
            choose(index)
            return true
        }
        return false
    }

    private func choose(_ index: Int) {
        guard state.skills.indices.contains(index) else { return }
        state.selectedIndex = index
        resolve(.skill(state.skills[index]))
    }

    private func resolve(_ result: PickerResult) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: result)
    }
}

// MARK: - View

struct SkillPickerView: View {
    @ObservedObject var state: SkillPickerState
    var onChoose: (Int) -> Void

    private static let visibleRows = 8
    private static let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if state.ready {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(state.status)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            if state.skills.count > Self.visibleRows {
                ScrollView { rows }
                    .frame(height: Self.rowHeight * CGFloat(Self.visibleRows))
            } else {
                rows
            }

            Text(state.ready ? "↑↓ choose · ⏎ apply · esc paste as-is" : "⏎ applies when ready · esc paste as-is")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .fixedSize()
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(Array(state.skills.enumerated()), id: \.element.id) { index, skill in
                row(index: index, skill: skill)
            }
        }
    }

    private func row(index: Int, skill: SkillChoice) -> some View {
        let selected = index == state.selectedIndex
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(skill.name)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in if inside { state.selectedIndex = index } }
        .onTapGesture { onChoose(index) }
    }
}
