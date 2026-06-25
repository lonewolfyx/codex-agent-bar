import AppKit

enum AppIcon {
    static func image() -> NSImage? {
        loadImage(named: "AppIcon", fallbackPath: "Assets/app-icon.png")
    }

    static func menuBarImage() -> NSImage? {
        loadImage(named: "MenuBarIcon", fallbackPath: "Assets/app-icon-light.png")
    }

    private static func loadImage(
        named resourceName: String,
        fallbackPath: String,
        sourceFilePath: String = #filePath
    ) -> NSImage? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        for path in fallbackCandidates(for: fallbackPath, sourceFilePath: sourceFilePath) {
            if FileManager.default.fileExists(atPath: path),
               let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    private static func fallbackCandidates(for fallbackPath: String, sourceFilePath: String) -> [String] {
        let workingDirectoryPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(fallbackPath)
            .path
        let sourceRootPath = URL(fileURLWithPath: sourceFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(fallbackPath)
            .path

        var candidates: [String] = []
        for path in [workingDirectoryPath, sourceRootPath] where !candidates.contains(path) {
            candidates.append(path)
        }
        return candidates
    }
}
