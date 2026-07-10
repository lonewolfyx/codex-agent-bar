import AppKit
import Foundation

struct CodexCLIResolver {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let bundledAppNames = ["ChatGPT.app", "Codex.app"]
    private static let bundledCLIComponents = ["Contents", "Resources", "codex"]

    static func resolve(
        fileManager: FileManager = .default,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        homeDirectory: URL? = nil,
        registeredApplicationURL: URL? = registeredCodexApplicationURL(),
        applicationDirectories: [URL]? = nil,
        fallbackBinDirectories: [URL]? = nil
    ) -> String? {
        let homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
        ]

        let registeredApplicationCandidates: [URL] = registeredApplicationURL.map {
            [bundledCLIURL(in: $0)]
        } ?? []
        let standardApplicationCandidates: [URL] = bundledAppNames.flatMap { appName in
            applicationDirectories.map { directory in
                bundledCLIURL(in: directory.appendingPathComponent(appName, isDirectory: true))
            }
        }
        let bundledCandidates = registeredApplicationCandidates + standardApplicationCandidates

        let pathCandidates = (environmentPath ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }

        let fallbackBinDirectories = fallbackBinDirectories ?? [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
        let fallbackCandidates = fallbackBinDirectories.map { $0.appendingPathComponent("codex") }

        let nvmRoot = homeDirectory
            .appendingPathComponent(".nvm", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent("node", isDirectory: true)
        let nvmCandidates = ((try? fileManager.contentsOfDirectory(atPath: nvmRoot.path)) ?? [])
            .sorted(by: >)
            .map {
                nvmRoot
                    .appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent("codex")
            }

        var visitedPaths = Set<String>()
        for candidate in bundledCandidates + pathCandidates + fallbackCandidates + nvmCandidates {
            let path = candidate.standardizedFileURL.path
            guard visitedPaths.insert(path).inserted else {
                continue
            }

            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private static func registeredCodexApplicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: codexBundleIdentifier)
    }

    private static func bundledCLIURL(in applicationURL: URL) -> URL {
        bundledCLIComponents.reduce(applicationURL) { url, component in
            url.appendingPathComponent(component)
        }
    }
}
