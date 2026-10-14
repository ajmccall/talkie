import Foundation
import os

/// Runs skills through the Codex CLI using its ChatGPT subscription login.
/// Ported from Reword's CodexService: ephemeral, read-only, every tool disabled,
/// structured JSON out.
struct CodexProvider: ModelProvider {
    let kind = ProviderKind.codex
    private let logger = Logger(subsystem: "talkie", category: "codex")

    // MARK: - Locating the CLI

    /// Search order. An nvm-installed Codex is a node script, so the newest nvm
    /// version is tried last and its directory is added to PATH when run.
    static func candidates(home: URL, nvmVersions: [String]) -> [String] {
        let fixed = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        let nvm = nvmVersions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { home.appendingPathComponent(".nvm/versions/node/\($0)/bin/codex").path }
        return fixed + nvm
    }

    func locateExecutable(override: String?) throws -> URL {
        let fm = FileManager.default
        let supplied = (override ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let paths: [String]
        if supplied.isEmpty {
            let home = fm.homeDirectoryForCurrentUser
            let versions = (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent(".nvm/versions/node").path)) ?? []
            paths = Self.candidates(home: home, nvmVersions: versions.filter { $0.hasPrefix("v") })
        } else {
            paths = [(supplied as NSString).expandingTildeInPath]
        }
        guard let path = paths.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            throw ProviderError.notFound(.codex)
        }
        return URL(fileURLWithPath: path)
    }

    /// Keeps networking/keychain environment, drops API billing and desktop-agent
    /// routing, and puts the CLI's own directory on PATH so a node shim finds node.
    static func environment(for executable: URL, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base.filter { key, _ in
            if key == "CODEX_HOME" { return true }
            if key.hasPrefix("CODEX_") || key.hasPrefix("OPENAI_") || key.hasPrefix("OTEL_") { return false }
            return true
        }
        let binDir = executable.deletingLastPathComponent().path
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path.split(separator: ":").contains(Substring(binDir)) ? path : "\(binDir):\(path)"
        env["NO_COLOR"] = "1"
        env["RUST_LOG"] = "off"
        return env
    }

    // MARK: - Connection

    func checkConnection(executable: URL) async throws -> ProviderAccount {
        let result = try await withTimeout(seconds: 15) {
            try await Subprocess.run(
                executable: executable,
                arguments: ["-c", "forced_login_method=\"chatgpt\"", "login", "status"],
                environment: Self.environment(for: executable)
            )
        }
        let status = (result.stdoutText + result.stderrText).lowercased()
        if status.contains("api key") || status.contains("api_key") { throw ProviderError.apiKeyLogin(.codex) }
        guard result.status == 0, status.contains("chatgpt") else { throw ProviderError.signedOut(.codex) }
        return ProviderAccount(summary: "ChatGPT")
    }

    // MARK: - Transform

    static let disabledFeatures = ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "multi_agent",
                                   "browser_use", "computer_use", "image_generation", "skill_search", "sleep_tool"]

    static func arguments(schema: URL, output: URL, model: String) -> [String] {
        var arguments = ["-a", "never", "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check",
                         "--sandbox", "read-only", "--color", "never", "--json",
                         "--output-schema", schema.path, "--output-last-message", output.path,
                         "-c", "forced_login_method=\"chatgpt\"", "-c", "project_doc_max_bytes=0",
                         "-c", "model_reasoning_effort=\"low\"", "-c", "web_search=\"disabled\""]
        for feature in disabledFeatures { arguments += ["--disable", feature] }
        arguments += ["--enable", "skip_host_skill_discovery"]
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { arguments += ["--model", model] }
        arguments.append("-")
        return arguments
    }

    func transform(_ text: String, skill: String, model: String, executable: URL) async throws -> String {
        let prompt = try SkillPrompt.make(skill: skill, transcript: text)
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Talkie-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let schema = directory.appendingPathComponent("response-schema.json")
        let output = directory.appendingPathComponent("result.json")
        try Data(SkillResponse.schema.utf8).write(to: schema)

        let started = Date()
        let result = try await Subprocess.run(
            executable: executable,
            arguments: Self.arguments(schema: schema, output: output, model: model),
            environment: Self.environment(for: executable),
            directory: directory,
            input: Data(prompt.utf8)
        )
        try Task.checkCancellation()
        logger.info("codex exec finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s with status \(result.status)")
        guard result.status == 0 else {
            throw Self.diagnose(result.stderrText + result.stdoutText)
        }
        guard let data = try? Data(contentsOf: output) else { throw ProviderError.invalidResponse }
        return try SkillResponse.decode(data)
    }

    static func diagnose(_ text: String) -> ProviderError {
        let lower = text.lowercased()
        if lower.contains("usage limit") || lower.contains("rate limit") || lower.contains("quota") {
            return .service("Codex allowance or rate limit reached")
        }
        if lower.contains("unauthorized") || lower.contains("401") || lower.contains("not logged in") || lower.contains("token expired") {
            return .signedOut(.codex)
        }
        if lower.contains("model"), lower.contains("not supported") || lower.contains("not found") || lower.contains("does not exist") {
            return .service("Model not available for this account")
        }
        if lower.contains("connect") || lower.contains("dns") || lower.contains("network") || lower.contains("stream disconnected") {
            return .service("Could not reach Codex")
        }
        return .service("Codex failed")
    }
}
