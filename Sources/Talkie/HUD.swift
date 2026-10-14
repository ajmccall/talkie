import AppKit
import SwiftUI

/// A small floating pill at the bottom of the screen showing what Talkie is doing.
/// It never takes focus, so the text lands in whatever app you were using.
@MainActor
final class HUD {
    struct Model {
        enum Kind { case recording, warning, working, success, failure }
        var kind: Kind
        var text: String
    }

    private let panel: NSPanel
    private let state = HUDState()
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
    }

    func show(_ model: Model, autoHideAfter seconds: TimeInterval? = nil) {
        state.kind = model.kind
        state.text = model.text
        hideTask?.cancel()
        position()
        panel.orderFrontRegardless()
        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func setLevel(_ level: Float) {
        state.level = level
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }

    /// Bottom-centre of the screen the pointer is on, which is where the user is
    /// looking; `NSScreen.main` is meaningless for an app with no key window.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        panel.setContentSize(size)
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80)
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class HUDState: ObservableObject {
    @Published var kind: HUD.Model.Kind = .working
    @Published var text: String = ""
    @Published var level: Float = 0
}

struct HUDView: View {
    @ObservedObject var state: HUDState

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(state.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .fixedSize()
    }

    @ViewBuilder
    private var indicator: some View {
        switch state.kind {
        case .recording, .warning:
            Circle()
                .fill(state.kind == .warning ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + CGFloat(min(state.level, 1)) * 0.8)
                .animation(.easeOut(duration: 0.08), value: state.level)
        case .working:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
