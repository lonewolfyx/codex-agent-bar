import AppKit

enum AppIcon {
    static func image() -> NSImage? {
        loadImage(named: "AppIcon", fallbackPath: "Assets/app-icon.png")
    }

    static func menuBarImage() -> NSImage? {
        loadImage(named: "MenuBarIcon", fallbackPath: "Assets/app-icon-light.png")
    }

    private static func loadImage(named resourceName: String, fallbackPath: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let localIconPath = FileManager.default.currentDirectoryPath + "/" + fallbackPath
        if FileManager.default.fileExists(atPath: localIconPath) {
            return NSImage(contentsOfFile: localIconPath)
        }

        return nil
    }
}
