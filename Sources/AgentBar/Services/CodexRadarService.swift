import Foundation

struct CodexRadarService {
    private static let currentURL = URL(string: "https://codexradar.com/current.json")!
    private static let htmlURL = URL(string: "https://codexradar.com/")!

    func readModelReason(completion: @escaping @Sendable (Result<ModelReasonSnapshot, Error>) -> Void) {
        fetch(url: Self.currentURL) { result in
            switch result {
            case .success(let data):
                do {
                    completion(.success(try parseCurrentJSON(data)))
                } catch {
                    readModelReasonFromHTML(completion: completion)
                }
            case .failure:
                readModelReasonFromHTML(completion: completion)
            }
        }
    }

    private func readModelReasonFromHTML(completion: @escaping @Sendable (Result<ModelReasonSnapshot, Error>) -> Void) {
        fetch(url: Self.htmlURL) { result in
            switch result {
            case .success(let data):
                do {
                    completion(.success(try parseHTML(data)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func fetch(url: URL, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/json,text/html;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("codex-agent-bar/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if
                let response = response as? HTTPURLResponse,
                !(200..<300).contains(response.statusCode) {
                completion(.failure(CodexRadarError.requestFailed(response.statusCode)))
                return
            }

            guard let data, !data.isEmpty else {
                completion(.failure(CodexRadarError.emptyResponse))
                return
            }

            completion(.success(data))
        }.resume()
    }
}

private func parseCurrentJSON(_ data: Data) throws -> ModelReasonSnapshot {
    guard
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let modelIQ = root["model_iq"] as? [String: Any]
    else {
        throw CodexRadarError.parsingFailed("Missing model_iq")
    }

    var entries: [ModelReasonEntry] = []
    if let latest = modelIQ["latest"] as? [String: Any],
       let entry = parseJSONEntry(latest) {
        entries.append(entry)
    }

    if let comparisons = modelIQ["comparisons"] as? [String: Any] {
        for value in comparisons.values {
            guard let comparison = value as? [String: Any] else {
                continue
            }

            let latest = comparison["latest"] as? [String: Any]
            let source = latest ?? comparison
            if let entry = parseJSONEntry(
                source,
                fallbackModel: comparison["model"] as? String,
                fallbackReasoningEffort: comparison["reasoning_effort"] as? String
            ) {
                entries.append(entry)
            }
        }
    }

    return try makeSnapshot(entries: entries, sourceURL: URL(string: "https://codexradar.com/current.json")!)
}

private func parseJSONEntry(
    _ source: [String: Any],
    fallbackModel: String? = nil,
    fallbackReasoningEffort: String? = nil
) -> ModelReasonEntry? {
    guard let score = doubleValue(source["score"]) else {
        return nil
    }

    let model = normalizedModel((source["model"] as? String) ?? fallbackModel)
    let reasoningEffort = normalizedReasoningEffort((source["reasoning_effort"] as? String) ?? fallbackReasoningEffort)

    guard let model, let reasoningEffort else {
        return nil
    }

    return ModelReasonEntry(
        model: model,
        reasoningEffort: reasoningEffort,
        score: score,
        date: source["date"] as? String
    )
}

private func parseHTML(_ data: Data) throws -> ModelReasonSnapshot {
    guard let html = String(data: data, encoding: .utf8) else {
        throw CodexRadarError.parsingFailed("HTML is not UTF-8")
    }

    let pattern = #"<div\b[^>]*class="[^"]*\bmodel-iq-score-chip\b[^"]*"[^>]*>.*?<span>([^<]+)</span>\s*<strong>([\d.]+)</strong>"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
    let entries = matches.compactMap { match -> ModelReasonEntry? in
        guard
            let labelRange = Range(match.range(at: 1), in: html),
            let scoreRange = Range(match.range(at: 2), in: html),
            let score = Double(html[scoreRange])
        else {
            return nil
        }

        return parseHTMLEntry(label: String(html[labelRange]), score: score)
    }

    return try makeSnapshot(entries: entries, sourceURL: URL(string: "https://codexradar.com/")!)
}

private func parseHTMLEntry(label: String, score: Double) -> ModelReasonEntry? {
    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = trimmed.replacingOccurrences(of: " ", with: "-").split(separator: "-")

    guard components.count >= 3, let effort = components.last else {
        return nil
    }

    let reasoningEffort = normalizedReasoningEffort(String(effort))
    let model = normalizedModel(components.dropLast().joined(separator: "-"))

    guard let model, let reasoningEffort else {
        return nil
    }

    return ModelReasonEntry(model: model, reasoningEffort: reasoningEffort, score: score, date: nil)
}

private func makeSnapshot(entries: [ModelReasonEntry], sourceURL: URL) throws -> ModelReasonSnapshot {
    let uniqueEntries = uniqueModelReasonEntries(entries)
    guard let selected = sortedModelReasonEntries(uniqueEntries).first else {
        throw CodexRadarError.parsingFailed("No model reason scores found")
    }

    return ModelReasonSnapshot(
        selected: selected,
        entries: sortedModelReasonEntries(uniqueEntries),
        sourceURL: sourceURL,
        lastUpdated: Date()
    )
}

private func uniqueModelReasonEntries(_ entries: [ModelReasonEntry]) -> [ModelReasonEntry] {
    var seen = Set<String>()
    return entries.filter { entry in
        let key = "\(entry.model.lowercased())-\(entry.reasoningEffort.lowercased())"
        guard !seen.contains(key) else {
            return false
        }

        seen.insert(key)
        return true
    }
}

private func sortedModelReasonEntries(_ entries: [ModelReasonEntry]) -> [ModelReasonEntry] {
    entries.sorted { lhs, rhs in
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        let lhsReasonRank = reasoningRank(lhs.reasoningEffort)
        let rhsReasonRank = reasoningRank(rhs.reasoningEffort)
        if lhsReasonRank != rhsReasonRank {
            return lhsReasonRank > rhsReasonRank
        }

        let lhsModelRank = modelRank(lhs.model)
        let rhsModelRank = modelRank(rhs.model)
        if lhsModelRank != rhsModelRank {
            return rhsModelRank.lexicographicallyPrecedes(lhsModelRank)
        }

        return lhs.model.localizedStandardCompare(rhs.model) == .orderedAscending
    }
}

private func reasoningRank(_ value: String) -> Int {
    switch value.lowercased() {
    case "xhigh":
        return 3
    case "high":
        return 2
    case "medium":
        return 1
    default:
        return 0
    }
}

private func modelRank(_ value: String) -> [Int] {
    value
        .split { !$0.isNumber }
        .compactMap { Int($0) }
}

private func normalizedModel(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed.lowercased()
}

private func normalizedReasoningEffort(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.isEmpty ? nil : trimmed
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

private enum CodexRadarError: LocalizedError {
    case emptyResponse
    case requestFailed(Int)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Codex radar returned an empty response."
        case .requestFailed(let statusCode):
            return "Codex radar request failed with HTTP \(statusCode)."
        case .parsingFailed(let message):
            return "Codex radar parsing failed: \(message)."
        }
    }
}
