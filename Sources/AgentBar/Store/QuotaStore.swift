import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var tokenUsageSnapshot: TokenUsageSnapshot?
    @Published var tokenUsageErrorMessage: String?
    @Published var statusMessage = I18n.current.loadingQuota
    @Published var isLoading = false
    @Published var cliUpgradeMessage: String?
    @Published var cliUpgradeAlertMessage: String?
    @Published var modelReasonSnapshot: ModelReasonSnapshot?
    @Published private(set) var currentAccount: CodexAccount?

    private let client = CodexAppServerClient()
    private let accountService = CodexAccountService()
    private let rateLimitService = CodexRateLimitService()
    private let tokenUsageService = CodexTokenUsageService()
    private let radarService = CodexRadarService()
    private var refreshTimer: Timer?
    private var radarRefreshTimer: Timer?
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
        isLoading = true
        statusMessage = I18n.current.loadingQuota
        refreshModelReason()
        scheduleNextModelReasonRefresh()
        checkCodexCLIVersionThenStart()
    }

    private func checkCodexCLIVersionThenStart() {
        client.checkMinimumResetCreditsVersion { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.cliUpgradeMessage = nil
                    self.cliUpgradeAlertMessage = nil
                    self.refreshAccountAndRateLimits()
                    self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            self?.refreshRateLimitsOnly()
                        }
                    }
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        radarRefreshTimer?.invalidate()
        radarRefreshTimer = nil
        client.stop()
    }

    func refresh() {
        guard hasStarted, !isLoading else {
            return
        }

        refreshModelReason()
        refreshAccountAndRateLimits()
    }

    private func refreshModelReason() {
        radarService.readModelReason { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let snapshot):
                    self.modelReasonSnapshot = snapshot
                    self.printParsedModelReason(snapshot)
                case .failure(let error):
                    print("[AgentBar] Codex radar refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func scheduleNextModelReasonRefresh() {
        radarRefreshTimer?.invalidate()

        let nextRefreshDate = nextModelReasonRefreshDate(after: Date())
        radarRefreshTimer = Timer(fire: nextRefreshDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.refreshModelReason()
                self.scheduleNextModelReasonRefresh()
            }
        }

        if let radarRefreshTimer {
            RunLoop.main.add(radarRefreshTimer, forMode: .common)
        }
    }

    private func nextModelReasonRefreshDate(after date: Date) -> Date {
        let calendar = Calendar.current
        let refreshTimes = [(hour: 8, minute: 30), (hour: 14, minute: 30)]

        for refreshTime in refreshTimes {
            guard
                let candidate = calendar.nextDate(
                    after: calendar.startOfDay(for: date),
                    matching: DateComponents(hour: refreshTime.hour, minute: refreshTime.minute),
                    matchingPolicy: .nextTime
                ),
                candidate > date
            else {
                continue
            }

            return candidate
        }

        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: refreshTimes[0].hour, minute: refreshTimes[0].minute),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(18 * 60 * 60)
    }

    private func printParsedModelReason(_ snapshot: ModelReasonSnapshot) {
        let selected = snapshot.selected
        print(
            "[AgentBar] Parsed Codex radar model reason: \(selected.displayModel) \(selected.displayReasoningEffort) \(selected.score)"
        )
    }

    private func refreshAccountAndRateLimits() {
        isLoading = true
        cliUpgradeMessage = nil
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
        cliUpgradeMessage = nil
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
                    self.snapshot = snapshot.preservingResetCreditDetails(from: self.snapshot)
                    self.readTokenUsage(account: account)
                case .failure(let error):
                    self.apply(error: error)
                }
            }
        }
    }

    private func readTokenUsage(account: CodexAccount) {
        tokenUsageService.readTokenUsage(client: client) { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(let snapshot):
                    self.tokenUsageSnapshot = snapshot
                    self.tokenUsageErrorMessage = nil
                case .failure(let error):
                    self.tokenUsageErrorMessage = error.localizedDescription
                    print("[AgentBar] Token usage refresh failed: \(error.localizedDescription)")
                }

                self.statusMessage = account.planType.map { I18n.current.signedInAs($0) } ?? I18n.current.quotaLoaded
                self.isLoading = false
            }
        }
    }

    private func apply(error: Error) {
        if case QuotaError.unsupportedCodexCLIVersion(let current, let required) = error {
            statusMessage = I18n.current.loadingQuota
            cliUpgradeMessage = I18n.current.codexCLIUpgradeInlineMessage(current: current, required: required)
            cliUpgradeAlertMessage = I18n.current.codexCLIUpgradeAlertMessage(current: current, required: required)
            isLoading = false
            print("[AgentBar] Quota refresh failed: \(error.localizedDescription)")
            return
        }

        statusMessage = error.localizedDescription
        isLoading = false
        print("[AgentBar] Quota refresh failed: \(error.localizedDescription)")
    }
}
