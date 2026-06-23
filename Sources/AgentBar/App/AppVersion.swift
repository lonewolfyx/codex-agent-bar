import Foundation

enum AppVersion {
    static let shortVersion: String = {
        versionFromEnvFile()
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }()

    private static func versionFromEnvFile() -> String? {
        for url in versionEnvFileCandidates() {
            guard let values = parseEnvFile(at: url), let version = values["VERSION"], !version.isEmpty else {
                continue
            }
            return version
        }
        return nil
    }

    private static func versionEnvFileCandidates() -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.url(forResource: "version", withExtension: "env") {
            candidates.append(resourceURL)
        }

        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent("version.env"))

        if let executableURL = Bundle.main.executableURL {
            var directory = executableURL.deletingLastPathComponent()
            for _ in 0..<5 {
                candidates.append(directory.appendingPathComponent("version.env"))
                directory.deleteLastPathComponent()
            }
        }

        return candidates
    }

    private static func parseEnvFile(at url: URL) -> [String: String]? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var values: [String: String] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separatorIndex)
            let value = stripQuotes(String(line[valueStart...].trimmingCharacters(in: .whitespaces)))
            values[key] = value
        }

        return values
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }

        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}
