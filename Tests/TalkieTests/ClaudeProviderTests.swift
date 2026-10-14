import Foundation
import Testing
@testable import Talkie

@Suite("Claude provider")
struct ClaudeProviderTests {
    @Test func candidateOrderPutsNativeInstallFirstAndNewestNvmLast() {
        let home = URL(fileURLWithPath: "/Users/t")
        let paths = ClaudeProvider.candidates(home: home, nvmVersions: ["v24.11.0", "v24.20.0"])
        #expect(paths.first == "/Users/t/.local/bin/claude")
        #expect(paths.suffix(2) == [
            "/Users/t/.nvm/versions/node/v24.20.0/bin/claude",
            "/Users/t/.nvm/versions/node/v24.11.0/bin/claude",
        ])
    }

    @Test func overrideWinsAndMissingThrows() throws {
        let provider = ClaudeProvider()
        #expect(try provider.locateExecutable(override: "/bin/cat").path == "/bin/cat")
        #expect(throws: ProviderError.notFound(.claude)) { try provider.locateExecutable(override: "/nonexistent/claude") }
    }

    @Test func environmentScrubsApiRoutingAndSetsConfigDir() {
        let env = ClaudeProvider.environment(for: URL(fileURLWithPath: "/Users/t/.local/bin/claude"), configDirectory: "~/profile", base: [
            "HOME": "/Users/t", "PATH": "/usr/bin:/bin", "ANTHROPIC_API_KEY": "secret", "ANTHROPIC_AUTH_TOKEN": "secret",
            "ANTHROPIC_BASE_URL": "https://example.invalid", "CLAUDE_CODE_USE_BEDROCK": "1", "ANTHROPIC_PROFILE": "x",
            "CLAUDE_CONFIG_DIR": "/elsewhere", "HTTPS_PROXY": "proxy",
        ])
        #expect(env["HOME"] == "/Users/t")
        #expect(env["HTTPS_PROXY"] == "proxy")
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        #expect(env["ANTHROPIC_AUTH_TOKEN"] == nil)
        #expect(env["ANTHROPIC_BASE_URL"] == nil)
        #expect(env["CLAUDE_CODE_USE_BEDROCK"] == nil)
        #expect(env["ANTHROPIC_PROFILE"] == nil)
        #expect(env["CLAUDE_CONFIG_DIR"] == NSHomeDirectory() + "/profile")
        #expect(env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] == "1")
        #expect(env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1")
        #expect(env["PATH"] == "/Users/t/.local/bin:/usr/bin:/bin")
        let noConfig = ClaudeProvider.environment(for: URL(fileURLWithPath: "/usr/bin/claude"), configDirectory: " ", base: ["CLAUDE_CONFIG_DIR": "/x"])
        #expect(noConfig["CLAUDE_CONFIG_DIR"] == nil)
    }

    @Test func readsAuthStatus() throws {
        let signedIn = #"{"loggedIn": true, "authMethod": "claude.ai", "subscriptionType": "team"}"#
        #expect(try ClaudeProvider.account(fromAuthStatus: signedIn).summary == "claude.ai team")
        #expect(throws: ProviderError.signedOut(.claude)) {
            try ClaudeProvider.account(fromAuthStatus: #"{"loggedIn": false, "authMethod": "none"}"#)
        }
        #expect(throws: ProviderError.apiKeyLogin(.claude)) {
            try ClaudeProvider.account(fromAuthStatus: #"{"loggedIn": true, "authMethod": "apiKey"}"#)
        }
        #expect(throws: ProviderError.signedOut(.claude)) { try ClaudeProvider.account(fromAuthStatus: "garbage") }
    }

    @Test func argumentsLockTheRunDown() {
        let args = ClaudeProvider.arguments(model: "sonnet")
        #expect(args.first == "-p")
        #expect(args.contains("--json-schema") && args.contains(SkillResponse.schema))
        for (index, item) in args.enumerated() where item == "--tools" { #expect(args[index + 1] == "") }
        for (index, item) in args.enumerated() where item == "--permission-prompts" { #expect(args[index + 1] == "none") }
        #expect(args.contains("--no-session-persistence") && args.contains("--strict-mcp-config"))
        #expect(args.contains("--disable-slash-commands") && !args.contains("--bare"))
        #expect(args.contains("--model") && args.contains("sonnet"))
        #expect(!ClaudeProvider.arguments(model: "").contains("--model"))
    }

    @Test func decodesStructuredOutputAndErrors() throws {
        let ok = #"{"type":"result","is_error":false,"result":"{\"text\":\"Hi\"}","structured_output":{"text":"Hi there"}}"#
        #expect(try ClaudeProvider.decode(Data(ok.utf8), status: 0, stderr: "") == "Hi there")
        let rawOnly = #"{"type":"result","is_error":false,"result":"{\"text\":\"Raw\"}"}"#
        #expect(try ClaudeProvider.decode(Data(rawOnly.utf8), status: 0, stderr: "") == "Raw")
        let signedOut = #"{"is_error":true,"result":"Failed to authenticate: OAuth session expired"}"#
        #expect(throws: ProviderError.signedOut(.claude)) { try ClaudeProvider.decode(Data(signedOut.utf8), status: 1, stderr: "") }
        #expect(throws: ProviderError.service("Claude failed")) { try ClaudeProvider.decode(Data(), status: 1, stderr: "boom") }
        #expect(throws: ProviderError.invalidResponse) { try ClaudeProvider.decode(Data("{}".utf8), status: 0, stderr: "") }
    }

    @Test func diagnosesFailures() {
        #expect(ClaudeProvider.diagnose("429 rate limit") == .service("Claude allowance or rate limit reached"))
        #expect(ClaudeProvider.diagnose("fetch failed") == .service("Could not reach Claude"))
        #expect(ClaudeProvider.diagnose("???") == .service("Claude failed"))
    }
}

/// Opt-in live check against the real Claude Code CLI and account:
///   TALKIE_LIVE=1 swift test --filter ClaudeLiveTests
/// Honours CLAUDE_CONFIG_DIR from the shell so a profile login can be used.
@Suite("Claude live", .enabled(if: ProcessInfo.processInfo.environment["TALKIE_LIVE"] == "1"))
struct ClaudeLiveTests {
    @Test func rewordsThroughTheSubscription() async throws {
        Settings.claudeConfigDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let provider = ClaudeProvider()
        let executable = try provider.locateExecutable(override: nil)
        let account = try await provider.checkConnection(executable: executable)
        #expect(account.summary.hasPrefix("claude.ai"))
        let skillPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/skills/slack-reword/SKILL.md").path
        let skill = try SkillPrompt.load(at: skillPath)
        let text = "um so yeah I think the the deploy is basically done but uh someone should double check staging first"
        let started = Date()
        let result = try await withTimeout(seconds: Settings.skillTimeoutSeconds) {
            try await provider.transform(text, skill: skill, model: ProviderKind.claude.defaultModel, executable: executable)
        }
        print("LIVE RESULT (\(Date().timeIntervalSince(started))s): \(result)")
        #expect(!result.isEmpty)
        #expect(!result.lowercased().contains("um "))
    }
}
