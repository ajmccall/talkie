import Foundation

/// A model account Talkie can be connected to. Talkie never handles tokens
/// itself: each provider shells out to a CLI that holds the user's login,
/// the same way Reword drives the Codex CLI.
enum ProviderKind: String, CaseIterable, Sendable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    /// Claude Code is designed in but not implemented yet; see docs for the recipe.
    var isAvailable: Bool { self == .codex }

    var defaultModel: String {
        switch self {
        case .codex: return "gpt-6-astra"
        case .claude: return "sonnet"
        }
    }

    func makeProvider() -> (any ModelProvider)? {
        switch self {
        case .codex: return CodexProvider()
        case .claude: return nil
        }
    }
}

struct ProviderAccount: Equatable, Sendable {
    /// Short description shown in the menu, e.g. "ChatGPT".
    let summary: String
}

protocol ModelProvider: Sendable {
    var kind: ProviderKind { get }
    /// Finds the CLI, honouring an explicit path first.
    func locateExecutable(override: String?) throws -> URL
    /// Confirms the CLI is signed in with a subscription account.
    func checkConnection(executable: URL) async throws -> ProviderAccount
    /// Applies `skill` to `text` and returns the replacement text.
    func transform(_ text: String, skill: String, model: String, executable: URL) async throws -> String
}

enum ProviderError: LocalizedError, Equatable {
    case notFound(ProviderKind)
    case signedOut(ProviderKind)
    case apiKeyLogin(ProviderKind)
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let kind): return "\(kind.displayName) CLI not found. Install it or choose the executable."
        case .signedOut(.codex): return "Signed out. Run codex login in Terminal, then check the connection."
        case .signedOut(let kind): return "Signed out of \(kind.displayName)."
        case .apiKeyLogin(let kind): return "\(kind.displayName) is using an API key. Sign in with your subscription instead."
        case .invalidResponse: return "The model returned an incomplete result."
        case .service(let message): return message
        }
    }

    /// Short form for the HUD, which has one line.
    var shortDescription: String {
        switch self {
        case .notFound: return "CLI not found"
        case .signedOut: return "signed out"
        case .apiKeyLogin: return "API key login"
        case .invalidResponse: return "bad response"
        case .service(let message): return String(message.prefix(40))
        }
    }
}
