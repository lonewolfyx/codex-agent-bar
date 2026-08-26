import Foundation
@preconcurrency import UserNotifications

final class AppUpdateNotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let notificationActivated = Notification.Name("AppUpdateNotificationActivated")

    private static let notificationIdentifier = "com.lonewolfyx.AgentBar.update-ready"
    private static let notificationThreadIdentifier = "com.lonewolfyx.AgentBar.app-update"
    private static let lastNotifiedBuildVersionKey = "AppUpdateLastNotifiedBuildVersion"

    private let notificationCenter: UNUserNotificationCenter?
    private let userDefaults: UserDefaults
    private let stateLock = NSLock()
    private var inFlightBuildVersion: String?

    override init() {
        let notificationCenter = Self.isRunningFromAppBundle
            ? UNUserNotificationCenter.current()
            : nil
        self.notificationCenter = notificationCenter
        userDefaults = .standard
        super.init()
        notificationCenter?.delegate = self
    }

    func removeNotificationIfInstalled(buildVersion: String) {
        guard
            let notificationCenter,
            let notifiedBuildVersion = lastNotifiedBuildVersion(),
            buildVersion.compare(notifiedBuildVersion, options: .numeric) != .orderedAscending
        else {
            return
        }

        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    func notifyUpdateAvailable(displayVersion: String, buildVersion: String) {
        guard
            let notificationCenter,
            beginNotificationAttempt(buildVersion: buildVersion)
        else {
            return
        }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliverUpdateAvailableNotification(
                    displayVersion: displayVersion,
                    buildVersion: buildVersion
                )
            case .notDetermined:
                self.requestAuthorizationAndNotify(
                    displayVersion: displayVersion,
                    buildVersion: buildVersion
                )
            case .denied:
                self.finishNotificationAttempt(buildVersion: buildVersion, succeeded: false)
            @unknown default:
                self.finishNotificationAttempt(buildVersion: buildVersion, succeeded: false)
            }
        }
    }

    private func requestAuthorizationAndNotify(displayVersion: String, buildVersion: String) {
        guard let notificationCenter else {
            finishNotificationAttempt(buildVersion: buildVersion, succeeded: false)
            return
        }

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard let self else {
                return
            }

            guard granted else {
                self.finishNotificationAttempt(buildVersion: buildVersion, succeeded: false)
                return
            }

            self.deliverUpdateAvailableNotification(
                displayVersion: displayVersion,
                buildVersion: buildVersion
            )
        }
    }

    private func deliverUpdateAvailableNotification(displayVersion: String, buildVersion: String) {
        guard let notificationCenter else {
            finishNotificationAttempt(buildVersion: buildVersion, succeeded: false)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = I18n.current.appUpdateAvailableTitle
        content.body = I18n.current.appUpdateAvailableMessage(version: displayVersion)
        content.sound = .default
        content.threadIdentifier = Self.notificationThreadIdentifier

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { [weak self] error in
            self?.finishNotificationAttempt(
                buildVersion: buildVersion,
                succeeded: error == nil
            )
        }
    }

    private func beginNotificationAttempt(buildVersion: String) -> Bool {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }

        guard
            userDefaults.string(forKey: Self.lastNotifiedBuildVersionKey) != buildVersion,
            inFlightBuildVersion == nil
        else {
            return false
        }

        inFlightBuildVersion = buildVersion
        return true
    }

    private func finishNotificationAttempt(buildVersion: String, succeeded: Bool) {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }

        if succeeded {
            userDefaults.set(buildVersion, forKey: Self.lastNotifiedBuildVersionKey)
        }

        if inFlightBuildVersion == buildVersion {
            inFlightBuildVersion = nil
        }
    }

    private func lastNotifiedBuildVersion() -> String? {
        stateLock.lock()
        defer {
            stateLock.unlock()
        }

        return userDefaults.string(forKey: Self.lastNotifiedBuildVersionKey)
    }

    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.identifier == Self.notificationIdentifier else {
            completionHandler([])
            return
        }

        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        defer {
            completionHandler()
        }

        guard
            response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            response.notification.request.identifier == Self.notificationIdentifier
        else {
            return
        }

        NotificationCenter.default.post(name: Self.notificationActivated, object: nil)
    }
}
