import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var statusMessage = I18n.current.loadingQuota
    @Published var isLoading = false
    @Published private(set) var currentAccount: CodexAccount?

    private let client = CodexAppServerClient()
    private let accountService = CodexAccountService()
    private let rateLimitService = CodexRateLimitService()
    private var refreshTimer: Timer?
    private var hasStarted = false

    init() {
        client.notificationHandler = { [weak self] method, _ in
            switch method {
            case "account/updated":
                self?.refreshAccountAndRateLimits()
            case "account/rateLimits/updated":
                self?.refreshRateLimitsOnly()
            default:
                return
            }
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        refreshAccountAndRateLimits()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRateLimitsOnly()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        client.stop()
    }

    private func refreshAccountAndRateLimits() {
        isLoading = true
        statusMessage = snapshot == nil ? I18n.current.loadingQuota : I18n.current.refreshingQuota

        client.start { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.readAccountAndRateLimits()
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    private func readAccountAndRateLimits() {
        accountService.readAccount(client: client) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let account):
                    self.validate(account: account)
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    private func validate(account: CodexAccount) {
        guard account.type != nil else {
            currentAccount = nil
            apply(error: QuotaError.notSignedIn)
            return
        }

        guard account.type == "chatgpt" else {
            currentAccount = nil
            apply(error: QuotaError.unsupportedAuthMode(account.type))
            return
        }

        currentAccount = account
        readRateLimits(account: account)
    }

    private func refreshRateLimitsOnly() {
        guard let currentAccount else {
            refreshAccountAndRateLimits()
            return
        }

        isLoading = true
        statusMessage = snapshot == nil ? I18n.current.loadingQuota : I18n.current.refreshingQuota

        client.start { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.readRateLimits(account: currentAccount)
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    private func readRateLimits(account: CodexAccount) {
        rateLimitService.readRateLimits(client: client) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.statusMessage = account.planType.map { I18n.current.signedInAs($0) } ?? I18n.current.quotaLoaded
                    self.isLoading = false
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    private func apply(error: Error) {
        statusMessage = error.localizedDescription
        isLoading = false
        print("[AgentBar] Quota refresh failed: \(error.localizedDescription)")
    }
}
