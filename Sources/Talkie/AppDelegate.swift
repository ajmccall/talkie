import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "talkie", category: "app")
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var cleanupMenuItem: NSMenuItem!
    private var skillStatusItem: NSMenuItem!
    private var connectItem: NSMenuItem!
    private var checkConnectionItem: NSMenuItem!
    private var chooseExecutableItem: NSMenuItem!
    private var disconnectItem: NSMenuItem!
    private var chooseSkillItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private let controller = Controller()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }
        controller.onConnectionChange = { [weak self] _ in
            self?.renderSkillSection()
        }
        renderSkillSection()
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

        menu.addItem(.separator())
        skillStatusItem = NSMenuItem(title: "Skills: off", action: nil, keyEquivalent: "")
        skillStatusItem.isEnabled = false
        menu.addItem(skillStatusItem)

        connectItem = NSMenuItem(title: "Connect Codex…", action: #selector(connectCodex), keyEquivalent: "")
        connectItem.target = self
        menu.addItem(connectItem)

        checkConnectionItem = NSMenuItem(title: "Check Connection", action: #selector(checkConnection), keyEquivalent: "")
        checkConnectionItem.target = self
        menu.addItem(checkConnectionItem)

        chooseExecutableItem = NSMenuItem(title: "Choose Codex Executable…", action: #selector(chooseExecutable), keyEquivalent: "")
        chooseExecutableItem.target = self
        menu.addItem(chooseExecutableItem)

        chooseSkillItem = NSMenuItem(title: "Choose Skill…", action: #selector(chooseSkill), keyEquivalent: "")
        chooseSkillItem.target = self
        menu.addItem(chooseSkillItem)

        disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "")
        disconnectItem.target = self
        menu.addItem(disconnectItem)
        menu.addItem(.separator())

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
            if Settings.skillEnabled, let path = Settings.skillPath {
                text = "Ready. Hold Fn to dictate, Fn+Shift for \(SkillPrompt.name(ofSkillAt: path))."
            } else {
                text = "Ready. Hold Fn to dictate."
            }
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

    // MARK: - Skills

    private func renderSkillSection() {
        let configured = Settings.providerKind != nil
        let kindName = Settings.providerKind?.displayName ?? "Codex"
        switch controller.connection {
        case .notConfigured: skillStatusItem.title = "Skills: off"
        case .checking: skillStatusItem.title = "\(kindName): checking…"
        case .connected(let account): skillStatusItem.title = "\(kindName): connected (\(account.summary))"
        case .failed(let message): skillStatusItem.title = "\(kindName): \(Self.shortStatus(message))"
        }
        connectItem.isHidden = configured
        checkConnectionItem.isHidden = !configured
        chooseExecutableItem.isHidden = !configured
        disconnectItem.isHidden = !configured
        chooseSkillItem.isHidden = !configured
        if let path = Settings.skillPath {
            chooseSkillItem.title = "Skill: \(SkillPrompt.name(ofSkillAt: path))…"
        } else {
            chooseSkillItem.title = "Choose Skill…"
        }
        render(controller.state)
    }

    private static func shortStatus(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("signed out") { return "signed out" }
        if lower.contains("not found") { return "not found" }
        if lower.contains("api key") { return "API key login" }
        return "connection failed"
    }

    @objc private func connectCodex() {
        controller.connect(kind: .codex)
        explainConnectionFailure(after: 20)
    }

    @objc private func checkConnection() {
        controller.checkConnection()
        explainConnectionFailure(after: 20)
    }

    /// If the check ends in failure, say what to do about it. Polls briefly since
    /// the check is asynchronous and the menu has already closed.
    private func explainConnectionFailure(after seconds: TimeInterval) {
        Task { @MainActor [weak self] in
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                guard let self else { return }
                switch self.controller.connection {
                case .checking: try? await Task.sleep(for: .milliseconds(200)); continue
                case .failed(let message):
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Could not connect"
                    alert.informativeText = message
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Choose Executable…")
                    if alert.runModal() == .alertSecondButtonReturn { self.chooseExecutable() }
                    return
                default: return
                }
            }
        }
    }

    @objc private func chooseExecutable() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.providerExecutableOverride = url.path
        controller.checkConnection()
        explainConnectionFailure(after: 20)
    }

    @objc private func chooseSkill() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a SKILL.md to apply on Fn+Shift"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        let skills = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
        if FileManager.default.fileExists(atPath: skills.path) { panel.directoryURL = skills }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.skillPath = url.path
        renderSkillSection()
    }

    @objc private func disconnect() {
        controller.disconnect()
        renderSkillSection()
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
