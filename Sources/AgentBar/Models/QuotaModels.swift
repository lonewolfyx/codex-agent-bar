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
            return I18n.current.codexCLINotFound
        case .appServerStartFailed(let message):
            return I18n.current.appServerStartFailed(message)
        case .initializationFailed(let message):
            return I18n.current.initializationFailed(message)
        case .notSignedIn:
            return I18n.current.notSignedIn
        case .unsupportedAuthMode(let mode):
            return I18n.current.unsupportedAuthMode(mode)
        case .rpcError(let message):
            return message
        case .parsingFailed(let message):
            return I18n.current.parsingFailed(message)
        }
    }
}
