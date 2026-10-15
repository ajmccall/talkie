import Foundation
import os

/// Runs skills through the Claude Code CLI using its claude.ai subscription login.
/// Same shape as `CodexProvider`: one-shot print mode, no tools, no hooks, no
/// memory or CLAUDE.md files, structured JSON out.
struct ClaudeProvider: ModelProvider {
    let kind = ProviderKind.claude
    private let logger = Logger(subsystem: "talkie", category: "claude")

    // MARK: - Locating the CLI

    /// The native installer puts a symlink in ~/.local/bin; npm installs land in
    /// Homebrew, /usr/local, or an nvm version (newest tried last).
    static func candidates(home: URL, nvmVersions: [String]) -> [String] {
        let fixed = [
            home.appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        let nvm = nvmVersions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { home.appendingPathComponent(".nvm/versions/node/\($0)/bin/claude").path }
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
            throw ProviderError.notFound(.claude)
        }
        return URL(fileURLWithPath: path)
    }

    /// Drops API-key and proxy routing so the subscription login is used, turns
    /// off project files and memory, and points at the chosen config folder.
    static func environment(for executable: URL, configDirectory: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base.filter { key, _ in
            if key == "ANTHROPIC_API_KEY" || key == "ANTHROPIC_AUTH_TOKEN" || key == "ANTHROPIC_BASE_URL"
                || key == "ANTHROPIC_PROFILE" || key == "CLAUDE_CONFIG_DIR" { return false }
            if key.hasPrefix("CLAUDE_CODE_USE_") { return false }
            return true
        }
        let configDirectory = (configDirectory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !configDirectory.isEmpty { env["CLAUDE_CONFIG_DIR"] = (configDirectory as NSString).expandingTildeInPath }
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["DISABLE_AUTOUPDATER"] = "1"
        let binDir = executable.deletingLastPathComponent().path
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path.split(separator: ":").contains(Substring(binDir)) ? path : "\(binDir):\(path)"
        env["NO_COLOR"] = "1"
        return env
    }

    private func environment(for executable: URL) -> [String: String] {
        Self.environment(for: executable, configDirectory: Settings.claudeConfigDirectory)
    }

    // MARK: - Connection

    /// `claude auth status` prints JSON and exits 1 when signed out.
    static func account(fromAuthStatus text: String) throws -> ProviderAccount {
        guard let start = text.firstIndex(of: "{"),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [String: Any] else {
            throw ProviderError.signedOut(.claude)
        }
        let method = (object["authMethod"] as? String ?? "").lowercased()
        if method.contains("api") { throw ProviderError.apiKeyLogin(.claude) }
        guard object["loggedIn"] as? Bool == true else { throw ProviderError.signedOut(.claude) }
        let plan = (object["subscriptionType"] as? String).map { " \($0)" } ?? ""
        return ProviderAccount(summary: "claude.ai\(plan)")
    }

    func checkConnection(executable: URL) async throws -> ProviderAccount {
        let result = try await withTimeout(seconds: 15) {
            try await Subprocess.run(executable: executable, arguments: ["auth", "status"], environment: environment(for: executable))
        }
        return try Self.account(fromAuthStatus: result.stdoutText)
    }

    // MARK: - Transform

    static let systemPrompt = "You are a text transformation engine. Follow the instructions in the message, "
        + "use no tools, and reply with only the JSON object the response schema requires."

    /// `streaming` swaps the one-shot text prompt for stream-json on both ends,
    /// which lets the process be launched before the prompt exists.
    static func arguments(model: String, streaming: Bool = false) -> [String] {
        var arguments = ["-p"]
        if streaming {
            arguments += ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        } else {
            arguments += ["--output-format", "json"]
        }
        arguments += ["--json-schema", SkillResponse.schema,
                      "--system-prompt", systemPrompt, "--effort", "low",
                      "--tools", "", "--disallowedTools", "mcp__*", "--strict-mcp-config",
                      "--disable-slash-commands", "--no-session-persistence", "--permission-prompts", "none"]
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { arguments += ["--model", model] }
        return arguments
    }

    private static func makeScratchDirectory() throws -> URL {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Talkie-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    func transform(_ text: String, skill: String, model: String, executable: URL) async throws -> String {
        let prompt = try SkillPrompt.make(skill: skill, transcript: text)
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let started = Date()
        let result = try await Subprocess.run(
            executable: executable,
            arguments: Self.arguments(model: model),
            environment: environment(for: executable),
            directory: directory,
            input: Data(prompt.utf8)
        )
        try Task.checkCancellation()
        logger.info("claude -p finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s with status \(result.status)")
        return try Self.decode(result.stdout, status: result.status, stderr: result.stderrText)
    }

    /// Launches `claude -p` in stream-json mode with stdin held open. Node
    /// start-up, config and login happen now; the prompt is sent by `transform`.
    func prepare(model: String, executable: URL) throws -> (any PreparedTransform)? {
        let directory = try Self.makeScratchDirectory()
        do {
            let handle = try Subprocess.spawn(
                executable: executable,
                arguments: Self.arguments(model: model, streaming: true),
                environment: environment(for: executable),
                directory: directory
            )
            logger.info("claude -p pre-warmed")
            return WarmTransform(handle: handle, directory: directory, logger: logger)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// One user message on stdin, as the stream-json input format expects.
    static func streamMessage(prompt: String) throws -> Data {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": prompt]]
        var data = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    private final class WarmTransform: PreparedTransform, @unchecked Sendable {
        private let handle: Subprocess.Handle
        private let directory: URL
        private let logger: Logger

        init(handle: Subprocess.Handle, directory: URL, logger: Logger) {
            self.handle = handle
            self.directory = directory
            self.logger = logger
        }

        var startedAt: Date { handle.startedAt }
        var isRunning: Bool { handle.isRunning }

        func transform(_ text: String, skill: String) async throws -> String {
            defer { try? FileManager.default.removeItem(at: directory) }
            let prompt = try SkillPrompt.make(skill: skill, transcript: text)
            let started = Date()
            // A stream-json session stays alive after stdin closes, so stop
            // waiting the moment the result event has been written.
            let result = try await handle.finish(input: try ClaudeProvider.streamMessage(prompt: prompt),
                                                 completeWhen: ClaudeProvider.isResultLine)
            try Task.checkCancellation()
            logger.info("pre-warmed claude -p answered in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s (alive \(Date().timeIntervalSince(self.startedAt), format: .fixed(precision: 1))s) with status \(result.status)")
            return try ClaudeProvider.decodeStream(result.stdout, status: result.status, stderr: result.stderrText)
        }

        func discard() {
            handle.discard()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The `json` output format is one object: `structured_output` holds the
    /// schema-shaped reply, `result` the raw text, `is_error` a failure message.
    static func decode(_ data: Data, status: Int32, stderr: String) throws -> String {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return try decode(result: object, status: status, stderr: stderr)
    }

    /// Cheap test for the final stream-json event, run on every stdout line.
    static func isResultLine(_ line: String) -> Bool {
        line.hasPrefix("{") && line.contains(#""type":"result""#)
    }

    /// The `stream-json` output format is one JSON object per line; the last
    /// one with `"type":"result"` has the same shape as the `json` format.
    static func decodeStream(_ data: Data, status: Int32, stderr: String) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        let result = text.split(separator: "\n").reversed().lazy
            .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            .first { $0["type"] as? String == "result" }
        return try decode(result: result, status: status, stderr: stderr)
    }

    private static func decode(result object: [String: Any]?, status: Int32, stderr: String) throws -> String {
        if let object, object["is_error"] as? Bool == true || status != 0 {
            throw diagnose((object["result"] as? String ?? "") + " " + stderr)
        }
        guard status == 0 else { throw diagnose(stderr) }
        if let structured = object?["structured_output"], let data = try? JSONSerialization.data(withJSONObject: structured) {
            return try SkillResponse.decode(data)
        }
        if let raw = object?["result"] as? String { return try SkillResponse.decode(Data(raw.utf8)) }
        throw ProviderError.invalidResponse
    }

    static func diagnose(_ text: String) -> ProviderError {
        let lower = text.lowercased()
        if lower.contains("usage limit") || lower.contains("rate limit") || lower.contains("quota") || lower.contains("429") {
            return .service("Claude allowance or rate limit reached")
        }
        if lower.contains("authenticate") || lower.contains("not logged in") || lower.contains("oauth") || lower.contains("401") {
            return .signedOut(.claude)
        }
        if lower.contains("model"), lower.contains("not supported") || lower.contains("not found") || lower.contains("invalid") {
            return .service("Model not available for this account")
        }
        if lower.contains("connect") || lower.contains("dns") || lower.contains("network") || lower.contains("fetch failed") {
            return .service("Could not reach Claude")
        }
        return .service("Claude failed")
    }
}
