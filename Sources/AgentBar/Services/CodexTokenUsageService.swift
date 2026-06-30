import Foundation

struct CodexTokenUsageService {
    func readTokenUsage(client: CodexAppServerClient, completion: @escaping @Sendable (Result<TokenUsageSnapshot, Error>) -> Void) {
        client.sendRequest(method: "account/usage/read") { result in
            switch result {
            case .success(let response):
                do {
                    completion(.success(try parseTokenUsageResponse(response)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseTokenUsageResponse(_ response: CodexAppServerClient.JSONDictionary) throws -> TokenUsageSnapshot {
        guard let result = response["result"] as? CodexAppServerClient.JSONDictionary else {
            throw QuotaError.parsingFailed(I18n.current.missingTokenUsageResult)
        }

        let payload = result["usage"] as? CodexAppServerClient.JSONDictionary ?? result
        let summary = payload["summary"] as? CodexAppServerClient.JSONDictionary
        let totalTokens = intValue(summary?["lifetimeTokens"])
        let bucketObjects = payload["dailyUsageBuckets"] as? [CodexAppServerClient.JSONDictionary]
        let parsedBuckets = bucketObjects?.compactMap(parseDailyUsageBucket) ?? []
        let usageByDay = parsedBuckets.reduce(into: [Date: Int]()) { result, bucket in
            result[calendar.startOfDay(for: bucket.date), default: 0] += bucket.tokens
        }
        let dailyUsage = lastThirtyDays(usageByDay: usageByDay)
        let today = dailyUsage.last?.tokens ?? 0
        let yesterday = dailyUsage.dropLast().last?.tokens ?? 0
        let recentTotal = dailyUsage.reduce(0) { $0 + $1.tokens }
        let weeklyAverage = Int((Double(recentTotal) / 30.0 * 7.0).rounded())
        let fallbackTotal = bucketObjects == nil ? nil : parsedBuckets.reduce(0) { $0 + $1.tokens }

        return TokenUsageSnapshot(
            todayTokens: today,
            yesterdayTokens: yesterday,
            totalTokens: totalTokens ?? fallbackTotal,
            averageWeeklyTokens: weeklyAverage,
            dailyUsage: dailyUsage,
            hasDailyUsageBuckets: bucketObjects != nil,
            lastUpdated: Date()
        )
    }

    private func parseDailyUsageBucket(_ bucket: CodexAppServerClient.JSONDictionary) -> TokenUsageDay? {
        guard
            let startDate = bucket["startDate"] as? String,
            let date = Self.dayFormatter.date(from: startDate)
        else {
            return nil
        }

        return TokenUsageDay(
            date: calendar.startOfDay(for: date),
            tokens: max(0, intValue(bucket["tokens"]) ?? 0)
        )
    }

    private func lastThirtyDays(usageByDay: [Date: Int]) -> [TokenUsageDay] {
        let today = calendar.startOfDay(for: Date())

        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 29, to: today) else {
                return nil
            }

            return TokenUsageDay(date: date, tokens: usageByDay[date] ?? 0)
        }
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

    private var calendar: Calendar {
        Calendar.current
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
