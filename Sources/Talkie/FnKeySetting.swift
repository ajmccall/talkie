import Foundation

/// The macOS "Press 🌐 key to" setting. Anything but "Do Nothing" (0) makes
/// each Fn press also open Dictation or the emoji picker, so Talkie asks for 0.
/// Same key and value as `defaults write com.apple.HIToolbox AppleFnUsageType -int 0`
/// in scripts/setup.sh.
enum FnKeySetting {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString

    /// 0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation.
    static var current: Int? {
        CFPreferencesCopyAppValue(key, domain) as? Int
    }

    static var isDoNothing: Bool { current == 0 }

    static func setDoNothing() {
        CFPreferencesSetAppValue(key, 0 as CFNumber, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

/// Deep links into System Settings used by the menu and the Welcome window.
enum SystemSettings {
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let keyboard = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
