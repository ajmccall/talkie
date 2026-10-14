import AppKit
import Carbon.HIToolbox

/// Puts text on the clipboard and sends ⌘V to the frontmost app.
/// Synthesising the keystroke needs the Accessibility permission.
///
/// Known limit: apps with Secure Keyboard Entry on (password fields, Terminal
/// with the option enabled) swallow synthetic keystrokes. The text is still on
/// the clipboard in that case.
enum Paster {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Returns false when the keystroke could not be sent; the text is still on the clipboard.
    @discardableResult
    static func pasteFromClipboard() -> Bool {
        guard isTrusted(prompt: false) else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
