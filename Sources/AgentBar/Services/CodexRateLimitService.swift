import Foundation

struct CodexRateLimitService {
    func readRateLimits(client: CodexAppServerClient, completion: @escaping @Sendable (Result<QuotaSnapshot, Error>) -> Void) {
        client.sendRequest(method: "account/rateLimits/read") { result in
            switch result {
            case .success(let response):
                do {
                    completion(.success(try parseRateLimitResponse(response)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseRateLimitResponse(_ response: CodexAppServerClient.JSONDictionary) throws -> QuotaSnapshot {
        guard let result = response["result"] as? CodexAppServerClient.JSONDictionary else {
            throw QuotaError.parsingFailed(I18n.current.missingRateLimitResult)
        }

        let fallbackBucket = result["rateLimits"] as? CodexAppServerClient.JSONDictionary
        let codexBucket = (result["rateLimitsByLimitId"] as? CodexAppServerClient.JSONDictionary)?["codex"] as? CodexAppServerClient.JSONDictionary
        let buckets = [codexBucket, fallbackBucket].compactMap { $0 }

        var windows: [QuotaWindow] = []
        for bucket in buckets {
            appendWindow(named: "primary", from: bucket, into: &windows)
            appendWindow(named: "secondary", from: bucket, into: &windows)
        }

        windows = uniqueWindows(windows).sorted { lhs, rhs in
            (lhs.windowDurationMins ?? Int.max) < (rhs.windowDurationMins ?? Int.max)
        }

        guard windows.count >= 2 else {
            throw QuotaError.parsingFailed(I18n.current.expectedQuotaWindows)
        }

        let selected = selectMenuWindows(from: windows)
        let snapshot = QuotaSnapshot(
            primary: selected.primary,
            secondary: selected.secondary,
            lastUpdated: Date()
        )

        printParsedQuota(snapshot)
        return snapshot
    }

    private func appendWindow(
        named fieldName: String,
        from bucket: CodexAppServerClient.JSONDictionary,
        into windows: inout [QuotaWindow]
    ) {
        guard let window = bucket[fieldName] as? CodexAppServerClient.JSONDictionary else {
            return
        }

        let duration = intValue(window["windowDurationMins"])
        let used = doubleValue(window["usedPercent"]) ?? 0
        let remaining = max(0, min(100, 100 - used))
        let resetTimestamp = doubleValue(window["resetsAt"])
        let resetDate = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        let title = windowTitle(durationMins: duration, fallback: bucket["limitName"] as? String ?? bucket["limitId"] as? String)
        let shortTitle = shortWindowTitle(durationMins: duration, fallback: title)

        windows.append(
            QuotaWindow(
                id: "\(bucket["limitId"] as? String ?? "codex")-\(fieldName)-\(duration.map(String.init) ?? "unknown")",
                title: "\(title) \(I18n.current.windowSuffix)",
                shortTitle: shortTitle,
                usedPercent: max(0, min(100, used)),
                remainingPercent: remaining,
                windowDurationMins: duration,
                resetsAt: resetDate
            )
        )
    }

    private func uniqueWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var seen = Set<String>()
        return windows.filter { window in
            let key = window.windowDurationMins.map(String.init) ?? window.id
            if seen.contains(key) {
                return false
            }

            seen.insert(key)
            return true
        }
    }

    private func selectMenuWindows(from windows: [QuotaWindow]) -> (primary: QuotaWindow, secondary: QuotaWindow) {
        let fiveHour = windows.first { $0.windowDurationMins == 300 }
        let oneWeek = windows.first { $0.windowDurationMins == 10080 }

        return (
            fiveHour ?? windows[0],
            oneWeek ?? windows[1]
        )
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? Double {
            return Int(value)
        }

        if let value = value as? String {
            return Int(value)
        }

        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? String {
            return Double(value)
        }

        return nil
    }

    private func windowTitle(durationMins: Int?, fallback: String?) -> String {
        guard let durationMins else {
            return fallback ?? I18n.current.quotaFallbackTitle
        }

        switch durationMins {
        case 300:
            return "5h"
        case 10080:
            return "1w"
        case ..<1440:
            return "\(max(1, durationMins / 60))h"
        default:
            return "\(max(1, durationMins / 1440))d"
        }
    }

    private func shortWindowTitle(durationMins: Int?, fallback: String) -> String {
        guard let durationMins else {
            return fallback
        }

        switch durationMins {
        case 300:
            return "5h"
        case 10080:
            return "1w"
        case ..<1440:
            return "\(max(1, durationMins / 60))h"
        default:
            return "\(max(1, durationMins / 1440))d"
        }
    }

    private func printParsedQuota(_ snapshot: QuotaSnapshot) {
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "primary": printableWindow(snapshot.primary, formatter: formatter),
            "secondary": printableWindow(snapshot.secondary, formatter: formatter),
            "lastUpdated": formatter.string(from: snapshot.lastUpdated),
        ]

        if
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8) {
            print("[AgentBar] Parsed quota data:\n\(text)")
        }
    }

    private func printableWindow(_ window: QuotaWindow, formatter: ISO8601DateFormatter) -> [String: Any] {
        [
            "title": window.title,
            "usedPercent": window.usedPercent,
            "remainingPercent": window.remainingPercent,
            "windowDurationMins": window.windowDurationMins ?? NSNull(),
            "resetsAt": window.resetsAt.map { formatter.string(from: $0) } ?? NSNull(),
        ]
    }
}
