import Foundation

struct QuotaWindow: Identifiable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let usedPercent: Double
    let remainingPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?
}

struct QuotaSnapshot: Sendable {
    var primary: QuotaWindow
    var secondary: QuotaWindow
    var lastUpdated: Date
}

struct CodexAccount: Sendable {
    let type: String?
    let email: String?
    let planType: String?
    let requiresOpenaiAuth: Bool
}

enum QuotaError: LocalizedError, Sendable {
    case codexCLINotFound
    case appServerStartFailed(String)
    case initializationFailed(String)
    case notSignedIn
    case unsupportedAuthMode(String?)
    case rpcError(String)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .codexCLINotFound:
            return "Cannot find codex CLI. Install Codex or add it to PATH."
        case .appServerStartFailed(let message):
            return "Failed to start codex app-server: \(message)"
        case .initializationFailed(let message):
            return "JSON-RPC initialization failed: \(message)"
        case .notSignedIn:
            return "Not signed in. Run Codex login first."
        case .unsupportedAuthMode(let mode):
            return "Current auth mode does not support ChatGPT rate limits\(mode.map { ": \($0)" } ?? ".")"
        case .rpcError(let message):
            return message
        case .parsingFailed(let message):
            return "Failed to parse rate limits: \(message)"
        }
    }
}
