import AppKit
import AVFoundation
import SwiftUI

/// Shown once on first launch and from the menu afterwards: what Talkie is,
/// a live checklist of what it needs, and a note that AI accounts are optional.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let state = WelcomeState()
    private var pollTimer: Timer?

    /// Called by the Models row's Retry button.
    var retryModels: (() -> Void)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Talkie"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView(state: state, actions: .init(
            openMicrophone: { NSWorkspace.shared.open(SystemSettings.microphone) },
            openAccessibility: { NSWorkspace.shared.open(SystemSettings.accessibility) },
            openKeyboard: { NSWorkspace.shared.open(SystemSettings.keyboard) },
            setFnDoNothing: { [weak self] in FnKeySetting.setDoNothing(); self?.refresh() },
            retryModels: { [weak self] in self?.retryModels?() },
            done: { [weak self] in self?.window.close() }
        )))
    }

    func show() {
        refresh()
        window.center()
        // Talkie is an accessory app; without activating, the window opens behind.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func update(models: Controller.State) {
        switch models {
        case .loadingModels(let detail):
            state.models = .loading(detail)
        case .failed(let message):
            state.models = .failed(message)
        default:
            state.models = .ready
        }
    }

    private func refresh() {
        state.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        state.accessibility = Paster.isTrusted(prompt: false)
        state.fnKeyDoNothing = FnKeySetting.isDoNothing
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

@MainActor
final class WelcomeState: ObservableObject {
    enum Models: Equatable {
        case loading(String), ready, failed(String)
    }
    @Published var microphone = false
    @Published var accessibility = false
    @Published var fnKeyDoNothing = false
    @Published var models: Models = .loading("starting")
}

struct WelcomeActions {
    var openMicrophone: () -> Void
    var openAccessibility: () -> Void
    var openKeyboard: () -> Void
    var setFnDoNothing: () -> Void
    var retryModels: () -> Void
    var done: () -> Void
}

struct WelcomeView: View {
    @ObservedObject var state: WelcomeState
    var actions: WelcomeActions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talkie").font(.title).bold()
                    Text("Push-to-talk dictation").foregroundStyle(.secondary)
                }
            }

            Text("Hold the Fn key, speak, let go. Talkie transcribes what you said, tidies it up, and pastes it into whatever app is in front.")
            Text("Everything runs on this Mac. Nothing leaves it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                row(ok: state.microphone, title: "Microphone",
                    detail: state.microphone ? "Allowed" : "Needed to hear you while Fn is held",
                    button: state.microphone ? nil : ("Open Settings…", actions.openMicrophone))
                row(ok: state.accessibility, title: "Accessibility",
                    detail: state.accessibility ? "Allowed" : "Needed to notice the Fn key and to paste (⌘V)",
                    button: state.accessibility ? nil : ("Open Settings…", actions.openAccessibility))
                row(ok: state.fnKeyDoNothing, title: "Fn key set to “Do Nothing”",
                    detail: state.fnKeyDoNothing ? "Set" : "Otherwise macOS also opens Dictation or emoji on each press. If it still does after this, log out and back in.",
                    button: state.fnKeyDoNothing ? nil : ("Set it", actions.setFnDoNothing),
                    secondary: state.fnKeyDoNothing ? nil : ("Keyboard Settings…", actions.openKeyboard))
                modelsRow
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Optional: AI skills").font(.headline)
                Text("Fn alone needs no account or sign-in. If you hold Fn+Shift, Talkie can hand the text to a skill through your Codex or Claude Code subscription. Connect one from the menu bar whenever you like, or never.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("Reopen this from the menu bar: Welcome / How Talkie works…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done", action: actions.done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var modelsRow: some View {
        let ok = state.models == .ready
        var detail: String
        var button: (String, () -> Void)?
        switch state.models {
        case .loading(let step): detail = "Downloading once (about 2.6 GB): \(step)"
        case .ready: detail = "Downloaded and ready"
        case .failed(let message): detail = message; button = ("Retry", actions.retryModels)
        }
        return row(ok: ok, title: "Speech models", detail: detail, button: button, busy: !ok && button == nil)
    }

    private func row(ok: Bool, title: String, detail: String,
                     button: (String, () -> Void)?, secondary: (String, () -> Void)? = nil,
                     busy: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if ok {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let button { Button(button.0, action: button.1).controlSize(.small) }
                if let secondary { Button(secondary.0, action: secondary.1).controlSize(.small).buttonStyle(.link) }
            }
        }
    }
}
