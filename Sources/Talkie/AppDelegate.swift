import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: "talkie", category: "app")
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var cleanupMenuItem: NSMenuItem!
    private var skillStatusItem: NSMenuItem!
    private var connectItem: NSMenuItem!
    private var connectClaudeItem: NSMenuItem!
    private var chooseConfigItem: NSMenuItem!
    private var checkConnectionItem: NSMenuItem!
    private var chooseExecutableItem: NSMenuItem!
    private var disconnectItem: NSMenuItem!
    private var skillsItem: NSMenuItem!
    private var skillsMenu: NSMenu!
    private var modelItem: NSMenuItem!
    private var modelMenu: NSMenu!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var retryMenuItem: NSMenuItem!
    private let controller = Controller()
    private let welcome = WelcomeWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        controller.onStateChange = { [weak self] state in
            self?.render(state)
        }
        controller.onConnectionChange = { [weak self] _ in
            self?.renderSkillSection()
        }
        welcome.retryModels = { [weak self] in self?.controller.reloadModels() }
        renderSkillSection()
        // First launch: explain before the system permission prompts land on top.
        if !Settings.welcomeShown {
            Settings.welcomeShown = true
            welcome.show()
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
        let welcomeItem = NSMenuItem(title: "Welcome / How Talkie works…", action: #selector(showWelcome), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        menu.addItem(.separator())

        cleanupMenuItem = NSMenuItem(title: "Clean up with Qwen3", action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupMenuItem.target = self
        cleanupMenuItem.state = Settings.cleanupEnabled ? .on : .off
        menu.addItem(cleanupMenuItem)

        let soundsItem = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        soundsItem.submenu = buildSoundsMenu()
        menu.addItem(soundsItem)

        menu.addItem(.separator())
        skillStatusItem = NSMenuItem(title: "Skills: off", action: nil, keyEquivalent: "")
        skillStatusItem.isEnabled = false
        menu.addItem(skillStatusItem)

        connectItem = NSMenuItem(title: "Connect Codex…", action: #selector(connectCodex), keyEquivalent: "")
        connectItem.target = self
        menu.addItem(connectItem)

        connectClaudeItem = NSMenuItem(title: "Connect Claude Code…", action: #selector(connectClaude), keyEquivalent: "")
        connectClaudeItem.target = self
        menu.addItem(connectClaudeItem)

        checkConnectionItem = NSMenuItem(title: "Check Connection", action: #selector(checkConnection), keyEquivalent: "")
        checkConnectionItem.target = self
        menu.addItem(checkConnectionItem)

        chooseExecutableItem = NSMenuItem(title: "Choose Codex Executable…", action: #selector(chooseExecutable), keyEquivalent: "")
        chooseExecutableItem.target = self
        menu.addItem(chooseExecutableItem)

        chooseConfigItem = NSMenuItem(title: "Choose Claude Config Folder…", action: #selector(chooseClaudeConfig), keyEquivalent: "")
        chooseConfigItem.target = self
        menu.addItem(chooseConfigItem)

        skillsMenu = NSMenu(title: "Skills")
        skillsMenu.delegate = self
        skillsItem = NSMenuItem(title: "Skills", action: nil, keyEquivalent: "")
        skillsItem.submenu = skillsMenu
        menu.addItem(skillsItem)

        modelMenu = NSMenu(title: "Model")
        modelMenu.delegate = self
        modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

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
        welcome.update(models: state)
        let symbol: String
        let text: String
        var failed = false
        switch state {
        case .loadingModels(let detail):
            symbol = "arrow.down.circle"
            text = "Loading models: \(detail)"
        case .idle:
            symbol = "mic"
            text = Settings.skillEnabled ? "Ready. Hold Fn to dictate, Fn+Shift to pick a skill." : "Ready. Hold Fn to dictate."
        case .recording:
            symbol = "mic.fill"
            text = "Recording…"
        case .processing(let detail):
            symbol = "waveform"
            text = detail
        case .choosing:
            symbol = "waveform"
            text = "Choosing a skill…"
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
        connectClaudeItem.isHidden = configured
        checkConnectionItem.isHidden = !configured
        chooseExecutableItem.isHidden = !configured
        chooseExecutableItem.title = "Choose \(kindName) Executable…"
        chooseConfigItem.isHidden = Settings.providerKind != .claude
        disconnectItem.isHidden = !configured
        skillsItem.isHidden = !configured
        let count = Settings.skillPaths.count
        skillsItem.title = count == 0 ? "Skills (none added)" : "Skills (\(count))"
        modelItem.isHidden = !configured
        modelItem.title = "Model: \(Settings.providerModel)"
        render(controller.state)
    }

    private static func shortStatus(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("signed out") { return "signed out" }
        if lower.contains("not found") { return "not found" }
        if lower.contains("api key") { return "API key login" }
        return "connection failed"
    }

    @objc private func connectClaude() {
        controller.connect(kind: .claude)
        explainConnectionFailure(after: 20)
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
                    if Settings.providerKind == .claude { alert.addButton(withTitle: "Choose Config Folder…") }
                    switch alert.runModal() {
                    case .alertSecondButtonReturn: self.chooseExecutable()
                    case .alertThirdButtonReturn: self.chooseClaudeConfig()
                    default: break
                    }
                    return
                default: return
                }
            }
        }
    }

    @objc private func chooseExecutable() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        let kind = Settings.providerKind ?? .codex
        panel.title = "Choose the \(kind.displayName) executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.setProviderExecutableOverride(url.path, for: kind)
        controller.checkConnection()
        explainConnectionFailure(after: 20)
    }

    /// For logins kept somewhere other than ~/.claude (a CLAUDE_CONFIG_DIR profile).
    @objc private func chooseClaudeConfig() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose the folder Claude Code is signed in from (usually ~/.claude)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.claudeConfigDirectory = url.path
        controller.checkConnection()
        explainConnectionFailure(after: 20)
    }

    /// The Skills submenu is rebuilt each time it opens: one entry per skill
    /// (tick = highlighted first in the picker), then Add Skill… and a Remove submenu.
    func menuWillOpen(_ menu: NSMenu) {
        if menu === modelMenu {
            rebuildModelMenu()
            return
        }
        guard menu === skillsMenu else { return }
        menu.removeAllItems()
        let paths = Settings.skillPaths
        let preselected = Settings.preselectedSkillPath
        if paths.isEmpty {
            let empty = NSMenuItem(title: "No skills added yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for path in paths {
            let name = SkillPrompt.name(ofSkillAt: path)
            let item = NSMenuItem(title: name, action: #selector(preselectSkill(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            item.state = path == preselected ? .on : .off
            item.toolTip = path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let add = NSMenuItem(title: "Add Skill…", action: #selector(addSkills), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        if !paths.isEmpty {
            let removeMenu = NSMenu(title: "Remove")
            for path in paths {
                let remove = NSMenuItem(title: SkillPrompt.name(ofSkillAt: path), action: #selector(removeSkill(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = path
                remove.toolTip = path
                removeMenu.addItem(remove)
            }
            let removeItem = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
            removeItem.submenu = removeMenu
            menu.addItem(removeItem)
        }
    }

    @objc private func preselectSkill(_ sender: NSMenuItem) {
        Settings.lastUsedSkillPath = sender.representedObject as? String
    }

    /// The model the skill runs on, as a radio group. The provider's choices
    /// plus whatever is currently stored (an older default, or a hand-set name).
    private func rebuildModelMenu() {
        modelMenu.removeAllItems()
        guard let kind = Settings.providerKind else { return }
        let current = Settings.providerModel
        var choices = kind.modelChoices
        if !current.isEmpty, !choices.contains(current) { choices.append(current) }
        for model in choices {
            let item = NSMenuItem(title: model, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            item.state = model == current ? .on : .off
            if model == kind.defaultModel { item.toolTip = "Default: fastest" }
            modelMenu.addItem(item)
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        Settings.providerModel = model
        renderSkillSection()
    }

    @objc private func removeSkill(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        Settings.skillPaths = SkillList.remove(path, from: Settings.skillPaths)
        if Settings.lastUsedSkillPath == path { Settings.lastUsedSkillPath = nil }
        renderSkillSection()
    }

    @objc private func addSkills() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add SKILL.md files to the Fn+Shift picker"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        let skills = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills")
        if FileManager.default.fileExists(atPath: skills.path) { panel.directoryURL = skills }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        Settings.skillPaths = SkillList.add(panel.urls.map(\.path), to: Settings.skillPaths)
        renderSkillSection()
    }

    @objc private func disconnect() {
        controller.disconnect()
        renderSkillSection()
    }

    /// Themes and volume as radio groups. Picking a theme plays its "pasted"
    /// sound so the options can be compared without dictating anything.
    private func buildSoundsMenu() -> NSMenu {
        let menu = NSMenu(title: "Sounds")
        for theme in SoundTheme.allCases {
            let item = NSMenuItem(title: theme.title, action: #selector(selectSoundTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.rawValue
            item.toolTip = theme.subtitle
            item.state = theme == Settings.soundTheme ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for volume in SoundVolume.allCases {
            let item = NSMenuItem(title: volume.title, action: #selector(selectSoundVolume(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = volume.rawValue
            item.state = volume == Settings.soundVolume ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let sample = NSMenuItem(title: "Play Start, Stop, Pasted", action: #selector(playSoundSample), keyEquivalent: "")
        sample.target = self
        menu.addItem(sample)
        return menu
    }

    @objc private func selectSoundTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = SoundTheme(rawValue: raw) else { return }
        Settings.soundTheme = theme
        for item in sender.menu?.items ?? [] where item.action == #selector(selectSoundTheme(_:)) {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
        Sounds.preview(.pasted, theme: theme)
    }

    @objc private func selectSoundVolume(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let volume = SoundVolume(rawValue: raw) else { return }
        Settings.soundVolume = volume
        for item in sender.menu?.items ?? [] where item.action == #selector(selectSoundVolume(_:)) {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
        Sounds.preview(.pasted, theme: Settings.soundTheme)
    }

    /// The three sounds of a dictation, spaced as they would be in use.
    @objc private func playSoundSample() {
        let theme = Settings.soundTheme
        Task { @MainActor in
            Sounds.preview(.recordingStarted, theme: theme)
            try? await Task.sleep(for: .milliseconds(900))
            Sounds.preview(.recordingStopped, theme: theme)
            try? await Task.sleep(for: .milliseconds(900))
            Sounds.preview(.pasted, theme: theme)
        }
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

    @objc private func showWelcome() {
        welcome.show()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(SystemSettings.accessibility)
    }

    @objc private func openMicrophone() {
        NSWorkspace.shared.open(SystemSettings.microphone)
    }
}
