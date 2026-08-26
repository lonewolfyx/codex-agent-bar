import Combine
import Foundation
import OSLog
import Sparkle

struct AppUpdateItem: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String
}

enum AppUpdateState: Equatable, Sendable {
    case unavailable
    case idle
    case checking
    case upToDate
    case available(AppUpdateItem)
    case downloading(AppUpdateItem)
    case ready(AppUpdateItem)
    case failed
}

@MainActor
final class AppUpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var state: AppUpdateState = .unavailable
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var nextScheduledCheckAt: Date?

    private let notificationService: AppUpdateNotificationService
    private let logger = Logger(subsystem: "com.lonewolfyx.AgentBar", category: "AppUpdate")
    private var updaterController: SPUStandardUpdaterController?
    private var manualCheckInProgress = false
    private var transientStateResetTask: Task<Void, Never>?

    override init() {
        notificationService = AppUpdateNotificationService()
        super.init()
    }

    var canPerformUserInitiatedCheck: Bool {
        guard let updater = updaterController?.updater else {
            return false
        }

        if case .checking = state {
            return false
        }

        return updater.canCheckForUpdates || updater.sessionInProgress
    }

    func start() {
        guard updaterController == nil else {
            return
        }

        removeInstalledUpdateNotification()

        guard Self.hasSparkleConfiguration else {
            state = .unavailable
            logger.warning("Sparkle configuration is unavailable; update checks are disabled")
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        state = .idle

        guard updaterController.updater.automaticallyChecksForUpdates else {
            logger.info("Automatic update checks are disabled")
            return
        }

        logger.info("Starting launch update check")
        updaterController.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        guard let updaterController else {
            return
        }

        cancelTransientStateReset()

        if updaterController.updater.sessionInProgress {
            updaterController.checkForUpdates(nil)
            return
        }

        guard updaterController.updater.canCheckForUpdates else {
            manualCheckInProgress = false
            return
        }

        manualCheckInProgress = true
        state = .checking
        updaterController.checkForUpdates(nil)
    }

    func presentCurrentUpdate() {
        updaterController?.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let wasUserInitiated = manualCheckInProgress
        manualCheckInProgress = false
        let updateItem = Self.updateItem(from: item)
        cancelTransientStateReset()
        state = .available(updateItem)
        lastCheckedAt = Date()

        logger.info("Found AgentBar update build \(updateItem.buildVersion, privacy: .public)")

        if !wasUserInitiated {
            notificationService.notifyUpdateAvailable(
                displayVersion: updateItem.displayVersion,
                buildVersion: updateItem.buildVersion
            )
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error _: Error) {
        let wasUserInitiated = manualCheckInProgress
        manualCheckInProgress = false
        lastCheckedAt = Date()

        switch state {
        case .available, .downloading, .ready:
            return
        case .unavailable, .idle, .checking, .upToDate, .failed:
            break
        }

        if wasUserInitiated {
            showTransientState(.upToDate)
        } else {
            cancelTransientStateReset()
            state = .idle
        }
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with _: NSMutableURLRequest
    ) {
        cancelTransientStateReset()
        state = .downloading(Self.updateItem(from: item))
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        cancelTransientStateReset()
        state = .ready(Self.updateItem(from: item))
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        cancelTransientStateReset()
        state = .available(Self.updateItem(from: item))
        logger.error("Failed to download update: \(error.localizedDescription, privacy: .public)")
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock _: @escaping () -> Void
    ) -> Bool {
        cancelTransientStateReset()
        state = .ready(Self.updateItem(from: item))
        return false
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        nextScheduledCheckAt = Date().addingTimeInterval(delay)
        logger.debug("Next update check scheduled in \(delay, privacy: .public) seconds")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        manualCheckInProgress = false

        guard case .checking = state else {
            return
        }

        lastCheckedAt = Date()
        showTransientState(.failed)
        logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor _: SPUUpdateCheck,
        error: Error?
    ) {
        manualCheckInProgress = false
        lastCheckedAt = Date()

        guard case .checking = state else {
            return
        }

        if let error {
            showTransientState(.failed)
            logger.error("Update cycle failed: \(error.localizedDescription, privacy: .public)")
        } else {
            state = .idle
        }
    }

    private func removeInstalledUpdateNotification() {
        guard let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return
        }

        notificationService.removeNotificationIfInstalled(buildVersion: buildVersion)
    }

    private func showTransientState(_ transientState: AppUpdateState) {
        cancelTransientStateReset()
        state = transientState
        transientStateResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, self?.state == transientState else {
                return
            }

            self?.state = .idle
        }
    }

    private func cancelTransientStateReset() {
        transientStateResetTask?.cancel()
        transientStateResetTask = nil
    }

    private static func updateItem(from item: SUAppcastItem) -> AppUpdateItem {
        AppUpdateItem(
            displayVersion: item.displayVersionString,
            buildVersion: item.versionString
        )
    }

    private static var hasSparkleConfiguration: Bool {
        guard
            let infoDictionary = Bundle.main.infoDictionary,
            let feedURL = trimmedInfoValue("SUFeedURL", in: infoDictionary),
            let publicKey = trimmedInfoValue("SUPublicEDKey", in: infoDictionary)
        else {
            return false
        }

        return !feedURL.isEmpty && !publicKey.isEmpty
    }

    private static func trimmedInfoValue(_ key: String, in infoDictionary: [String: Any]) -> String? {
        (infoDictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
