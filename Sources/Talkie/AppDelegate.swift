import AppKit
import ServiceManagement
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "talkie", category: "app")
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var cleanupMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Talkie")

        let menu = NSMenu()
        let title = NSMenuItem(title: "Talkie \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        cleanupMenuItem = NSMenuItem(title: "Clean up with Qwen3", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupMenuItem.target = self
        cleanupMenuItem.state = Settings.cleanupEnabled ? .on : .off
        menu.addItem(cleanupMenuItem)

        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginMenuItem)

        retryMenuItem = NSMenuItem(title: "Retry Loading Models", action: #selector(retryModels), keyEquivalent: "")
        retryMenuItem.target = self
        retryMenuItem.isHidden = true
        menu.addItem(retryMenuItem)

        menu.addItem(.separator())
        let openAX = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        openAX.target = self
        menu.addItem(openAX)

        let openMic = NSMenuItem(title: "Open Microphone Settings…", action: #selector(openMicrophone), keyEquivalent: "")
        openMic.target = self
        menu.addItem(openMic)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Talkie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func render(_ state: Controller.State) {
        let symbol: String
        let text: String
        var failed = false
        switch state {
        case .loadingModels(let detail):
            symbol = "arrow.down.circle"
            text = "Loading models: \(detail)"
        case .idle:
            symbol = "mic"
            text = "Ready. Hold Fn to dictate."
        case .recording:
            symbol = "mic.fill"
            text = "Recording…"
        case .processing(let detail):
            symbol = "waveform"
            text = detail
        case .failed(let message):
            symbol = "exclamationmark.triangle"
            text = message
            failed = true
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        statusMenuItem.title = text
        retryMenuItem.isHidden = !failed
    }

    @objc private func toggleCleanup() {
        Settings.cleanupEnabled.toggle()
        cleanupMenuItem.state = Settings.cleanupEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        launchAtLoginMenuItem.state = service.status == .enabled ? .on : .off
    }

    @objc private func retryModels() {
        controller.reloadModels()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openMicrophone() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
