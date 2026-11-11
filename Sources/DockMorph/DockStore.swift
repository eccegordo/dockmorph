import Foundation

struct DockSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol shown in the menu bar while this set is active.
    var symbol: String = "dock.rectangle"
    /// Absolute paths of the .app bundles, in Dock order.
    var apps: [String] = []
}

/// The user's dock sets, persisted to ~/Library/Application Support/DockMorph/sets.json.
final class DockStore: ObservableObject {
    static let shared = DockStore()
    static let changedNotification = Notification.Name("local.dockmorph.changed")

    @Published var sets: [DockSet] = [] { didSet { save() } }
    @Published var activeSetID: UUID? { didSet { save() } }
    @Published var lastError: String?
    @Published var launchAtLogin = LoginItem.isEnabled

    /// True when this launch created the sets file (first run).
    private(set) var isFirstRun = false

    private struct Saved: Codable {
        var sets: [DockSet]
        var activeSetID: UUID?
    }

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("sets.json") }
    private var isLoading = false

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockMorph", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        DockController.backupOriginalIfNeeded(to: directory.appendingPathComponent("original-dock-backup.plist"))

        if !load() {
            // First run: start with the Dock exactly as it is now.
            isFirstRun = true
            let current = DockSet(name: "My Dock", apps: DockController.currentAppPaths())
            isLoading = true
            sets = [current]
            activeSetID = current.id
            isLoading = false
            addMacOSDefaultSet()
            save()
        }
    }

    var activeSet: DockSet? { sets.first { $0.id == activeSetID } }

    // MARK: Actions

    /// Puts this set's apps in the Dock and restarts the Dock.
    func apply(_ set: DockSet) {
        do {
            try DockController.setApps(set.apps)
            activeSetID = set.id
            DockController.restartDock()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func addSet(name: String = "New Set", apps: [String] = []) -> DockSet {
        var unique = name
        var counter = 2
        while sets.contains(where: { $0.name == unique }) {
            unique = "\(name) \(counter)"
            counter += 1
        }
        let set = DockSet(name: unique, apps: apps)
        sets.append(set)
        return set
    }

    @discardableResult
    func addSetFromCurrentDock() -> DockSet {
        addSet(name: "Current Dock", apps: DockController.currentAppPaths())
    }

    /// Adds a set containing only the built-in apps from a factory-fresh macOS Dock.
    @discardableResult
    func addMacOSDefaultSet() -> DockSet {
        var set = addSet(name: "macOS Default Dock", apps: DockController.macOSDefaultAppPaths())
        set.symbol = "apple.logo"
        sets[sets.count - 1] = set
        return set
    }

    func remove(_ id: UUID) {
        sets.removeAll { $0.id == id }
        if activeSetID == id { activeSetID = nil }
    }

    // MARK: Persistence

    /// Reloads from disk. Returns false when there is no readable sets file.
    @discardableResult
    func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        isLoading = true
        sets = saved.sets
        activeSetID = saved.activeSetID
        isLoading = false
        return true
    }

    private func save() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(Saved(sets: sets, activeSetID: activeSetID)).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Couldn't save dock sets: \(error.localizedDescription)"
        }
    }
}
