import Foundation

/// Reads and writes the app section of the macOS Dock (`persistent-apps` in com.apple.dock).
/// Folders, the Downloads stack and the Trash (`persistent-others`) are never touched.
enum DockController {
    private static let key = "persistent-apps" as CFString

    /// Preferences domain to operate on. `DOCKMORPH_DOMAIN` redirects reads and writes to a
    /// scratch domain so the logic can be exercised without touching the real Dock.
    static var domainName: String {
        ProcessInfo.processInfo.environment["DOCKMORPH_DOMAIN"] ?? "com.apple.dock"
    }

    static var isRealDock: Bool { domainName == "com.apple.dock" }

    private static var domain: CFString { domainName as CFString }

    private static func rawTiles() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String else { return nil }
        let path: String
        if string.hasPrefix("file://") {
            guard let url = URL(string: string) else { return nil }
            path = url.path
        } else {
            path = string
        }
        return normalize(path)
    }

    static func normalize(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Paths of the apps currently pinned in the Dock, in order.
    static func currentAppPaths() -> [String] {
        var seen = Set<String>()
        return rawTiles().compactMap(path(of:)).filter { seen.insert($0).inserted }
    }

    /// The built-in apps macOS puts in a brand-new user's Dock, read from the Dock's own
    /// defaults so the list matches this macOS version. Only apps that ship with the system
    /// (under /System) are kept.
    static func macOSDefaultAppPaths() -> [String] {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/Resources/default.plist")
        var paths: [String] = []
        if let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let tiles = plist["persistent-apps"] as? [[String: Any]] {
            paths = tiles.compactMap(path(of:))
        }
        if paths.isEmpty {
            paths = ["Apps", "Safari", "Messages", "Mail", "Maps", "Photos", "FaceTime", "Calendar", "Contacts",
                     "Reminders", "Notes", "TV", "Music", "App Store", "System Settings"]
                .map { "/System/Applications/\($0).app" }
        }
        var seen = Set<String>()
        return paths.compactMap { path -> String? in
            // Safari lives in a cryptex; fall back to its /Applications alias if needed.
            let candidates = [path, "/Applications/" + (path as NSString).lastPathComponent]
            let systemApp = path.hasPrefix("/System/")
            return systemApp ? candidates.first { FileManager.default.fileExists(atPath: $0) } : nil
        }.filter { seen.insert($0).inserted }
    }

    /// Replaces the Dock's pinned apps. Apps that no longer exist on disk are skipped.
    /// Call `restartDock()` afterwards for the change to show up.
    static func setApps(_ paths: [String]) throws {
        // Reuse the Dock's own tile for apps that are already pinned (keeps its bookmark data).
        var existing: [String: [String: Any]] = [:]
        for tile in rawTiles() {
            if let path = path(of: tile), existing[path] == nil { existing[path] = tile }
        }

        let tiles: [[String: Any]] = paths.map(normalize).compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            if let tile = existing[path] { return tile }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return [
                "tile-type": "file-tile",
                "tile-data": [
                    "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                    "file-label": appName(path),
                    "file-type": 41,
                ] as [String: Any],
            ]
        }

        CFPreferencesSetAppValue(key, tiles as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            throw DockError.writeFailed
        }
    }

    /// Relaunches the Dock so it picks up the new preferences (`killall Dock`).
    static func restartDock() {
        guard isRealDock else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }

    /// Saves an untouched copy of the Dock's app tiles the first time Dock Morph runs.
    static func backupOriginalIfNeeded(to url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let tiles = rawTiles()
        guard !tiles.isEmpty,
              let data = try? PropertyListSerialization.data(fromPropertyList: tiles, format: .xml, options: 0)
        else { return }
        try? data.write(to: url)
    }

    static func appName(_ path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

enum DockError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "Couldn't write the Dock preferences."
    }
}
