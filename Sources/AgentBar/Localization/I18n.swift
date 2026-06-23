import Foundation

enum I18n {
    enum Language {
        case english
        case simplifiedChinese
    }

    struct Strings {
        let codexQuota: String
        let loadingQuota: String
        let refreshingQuota: String
        let quotaLoaded: String
        let loading: String
        let notRefreshed: String
        let lastRefreshPrefix: String
        let quit: String
        let currentSession: String
        let recentWeek: String
        let resetTimeUnavailable: String
        let resetSoon: String
        let refreshAtSuffix: String
        let dayUnit: String
        let hourUnit: String
        let minuteUnit: String
        let refreshAfterSuffix: String
        let dateLocaleIdentifier: String
        let dateFormat: String
        let quotaFallbackTitle: String
        let windowSuffix: String
        let codexCLINotFound: String
        let notSignedIn: String
        let appServerAlreadyStarting: String
        let processStopped: String
        let missingAccountResult: String
        let missingRateLimitResult: String
        let expectedQuotaWindows: String

        func signedInAs(_ planType: String) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "已登录：\(planType)"
            case .english:
                return "Signed in as \(planType)"
            }
        }

        func appServerStartFailed(_ message: String) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "启动 codex app-server 失败：\(message)"
            case .english:
                return "Failed to start codex app-server: \(message)"
            }
        }

        func initializationFailed(_ message: String) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "JSON-RPC 初始化失败：\(message)"
            case .english:
                return "JSON-RPC initialization failed: \(message)"
            }
        }

        func unsupportedAuthMode(_ mode: String?) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "当前登录方式不支持 ChatGPT 额度\(mode.map { "：\($0)" } ?? "。")"
            case .english:
                return "Current auth mode does not support ChatGPT rate limits\(mode.map { ": \($0)" } ?? ".")"
            }
        }

        func parsingFailed(_ message: String) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "解析额度信息失败：\(message)"
            case .english:
                return "Failed to parse rate limits: \(message)"
            }
        }

        func appServerExited(status: Int32) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "进程已退出，状态码 \(status)。"
            case .english:
                return "Process exited with status \(status)."
            }
        }

        func resetIn(days: Int, hours: String, minutes: String) -> String {
            if days > 0 {
                return "\(days)\(dayUnit)\(hours)\(hourUnit)\(minutes)\(minuteUnit)\(refreshAfterSuffix)"
            }

            return "\(hours)\(hourUnit)\(minutes)\(minuteUnit)\(refreshAfterSuffix)"
        }

        func refreshAt(_ dateText: String) -> String {
            switch I18n.language {
            case .simplifiedChinese:
                return "\(dateText)\(refreshAtSuffix)"
            case .english:
                return "Refresh at \(dateText)"
            }
        }

        func durationTitle(minutes: Int) -> String {
            switch minutes {
            case 300:
                return currentSession
            case 10080:
                return recentWeek
            case ..<1440:
                let hours = max(1, minutes / 60)
                switch I18n.language {
                case .simplifiedChinese:
                    return "\(hours) 小时\(windowSuffix)"
                case .english:
                    return "\(hours)h \(windowSuffix)"
                }
            default:
                let days = max(1, minutes / 1440)
                switch I18n.language {
                case .simplifiedChinese:
                    return "\(days) 天\(windowSuffix)"
                case .english:
                    return "\(days)d \(windowSuffix)"
                }
            }
        }
    }

    static var current: Strings {
        switch language {
        case .simplifiedChinese:
            return simplifiedChinese
        case .english:
            return english
        }
    }

    static var language: Language {
        let preferredLanguage = Locale.preferredLanguages.first ?? Locale.current.identifier
        let normalized = preferredLanguage
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized == "zh" || normalized.hasPrefix("zh-") {
            return .simplifiedChinese
        }

        return .english
    }

    private static let english = Strings(
        codexQuota: "Codex quota",
        loadingQuota: "Loading Codex quota...",
        refreshingQuota: "Refreshing Codex quota...",
        quotaLoaded: "Codex quota loaded.",
        loading: "loading...",
        notRefreshed: "Not refreshed",
        lastRefreshPrefix: "Last refresh",
        quit: "Quit",
        currentSession: "Current session",
        recentWeek: "Past 1 week",
        resetTimeUnavailable: "Reset time unavailable",
        resetSoon: "Reset soon",
        refreshAtSuffix: " refresh",
        dayUnit: "d ",
        hourUnit: "h ",
        minuteUnit: "m",
        refreshAfterSuffix: " until refresh",
        dateLocaleIdentifier: "en_US",
        dateFormat: "yyyy-MM-dd HH:mm",
        quotaFallbackTitle: "Quota",
        windowSuffix: "window",
        codexCLINotFound: "Cannot find codex CLI. Install Codex or add it to PATH.",
        notSignedIn: "Not signed in. Run Codex login first.",
        appServerAlreadyStarting: "app-server is already starting.",
        processStopped: "Process stopped.",
        missingAccountResult: "Missing account result.",
        missingRateLimitResult: "Missing rate limit result.",
        expectedQuotaWindows: "Expected primary and secondary quota windows."
    )

    private static let simplifiedChinese = Strings(
        codexQuota: "Codex 额度",
        loadingQuota: "正在加载 Codex 额度...",
        refreshingQuota: "正在刷新 Codex 额度...",
        quotaLoaded: "Codex 额度已加载。",
        loading: "加载中...",
        notRefreshed: "尚未刷新",
        lastRefreshPrefix: "上次刷新",
        quit: "退出",
        currentSession: "当前会话",
        recentWeek: "近 1 周",
        resetTimeUnavailable: "刷新时间不可用",
        resetSoon: "即将刷新",
        refreshAtSuffix: "刷新",
        dayUnit: "天",
        hourUnit: "时",
        minuteUnit: "分钟",
        refreshAfterSuffix: "后刷新",
        dateLocaleIdentifier: "zh_CN",
        dateFormat: "yyyy-MM-dd HH:mm",
        quotaFallbackTitle: "额度",
        windowSuffix: "窗口",
        codexCLINotFound: "找不到 codex CLI。请安装 Codex，或将其加入 PATH。",
        notSignedIn: "尚未登录。请先运行 Codex login。",
        appServerAlreadyStarting: "app-server 已在启动中。",
        processStopped: "进程已停止。",
        missingAccountResult: "缺少账户结果。",
        missingRateLimitResult: "缺少额度结果。",
        expectedQuotaWindows: "需要 primary 和 secondary 两个额度窗口。"
    )
}
