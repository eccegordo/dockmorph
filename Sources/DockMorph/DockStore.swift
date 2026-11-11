import Foundation

/// Sets that ship with Dock Morph. They are always present, can't be deleted, and can be
/// reverted to their factory contents at any time.
enum BuiltInSet: String, Codable, CaseIterable {
    case macOSDefault = "macos-default"

    var name: String {
        switch self {
        case .macOSDefault: return "macOS Default Dock"
        }
    }

    var symbol: String {
        switch self {
        case .macOSDefault: return "apple.logo"
        }
    }

    /// Factory contents, computed for this Mac and macOS version.
    func apps() -> [String] {
        switch self {
        case .macOSDefault: return DockController.macOSDefaultAppPaths()
        }
    }
}

struct DockSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol shown in the menu bar while this set is active.
    var symbol: String = "dock.rectangle"
    /// Absolute paths of the .app bundles, in Dock order.
    var apps: [String] = []
    /// A locked set can't be renamed, edited or deleted until it is unlocked.
    var locked = false
    /// Set for the sets that ship with Dock Morph.
    var builtIn: BuiltInSet?

    init(name: String, symbol: String = "dock.rectangle", apps: [String] = [],
         locked: Bool = false, builtIn: BuiltInSet? = nil) {
        self.name = name
        self.symbol = symbol
        self.apps = apps
        self.locked = locked
        self.builtIn = builtIn
    }

    // Decoded by hand so sets saved by older versions (without the newer fields) still load.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "dock.rectangle"
        apps = try values.decodeIfPresent([String].self, forKey: .apps) ?? []
        locked = try values.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        builtIn = (try? values.decodeIfPresent(String.self, forKey: .builtIn)).flatMap { $0 }
            .flatMap(BuiltInSet.init(rawValue:))
    }
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
        }
        ensureBuiltInSets()
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

    /// Built-in and locked sets can't be deleted.
    func canRemove(_ set: DockSet) -> Bool {
        set.builtIn == nil && !set.locked
    }

    func remove(_ id: UUID) {
        guard let set = sets.first(where: { $0.id == id }), canRemove(set) else { return }
        sets.removeAll { $0.id == id }
        if activeSetID == id { activeSetID = nil }
    }

    func setLocked(_ locked: Bool, for id: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[index].locked = locked
    }

    // MARK: Built-in sets

    /// Makes sure every built-in set exists. A set an older version created under the same
    /// name is adopted rather than duplicated. New built-in sets start out locked.
    private func ensureBuiltInSets() {
        var updated = sets
        for builtIn in BuiltInSet.allCases where !updated.contains(where: { $0.builtIn == builtIn }) {
            if let index = updated.firstIndex(where: { $0.builtIn == nil && $0.name == builtIn.name }) {
                updated[index].builtIn = builtIn
                // Lock it only if it still has its factory contents, so an edited one can be reverted.
                updated[index].locked = !isModified(updated[index])
            } else {
                updated.append(DockSet(name: builtIn.name, symbol: builtIn.symbol, apps: builtIn.apps(),
                                       locked: true, builtIn: builtIn))
            }
        }
        if updated != sets { sets = updated }
    }

    /// True when a built-in set no longer matches its factory name, icon or apps.
    func isModified(_ set: DockSet) -> Bool {
        guard let builtIn = set.builtIn else { return false }
        return set.name != builtIn.name || set.symbol != builtIn.symbol || set.apps != builtIn.apps()
    }

    /// Puts a built-in set back to its factory name, icon and apps. Locked sets are left alone.
    func revertToDefault(_ id: UUID) {
        guard let index = sets.firstIndex(where: { $0.id == id }),
              let builtIn = sets[index].builtIn, !sets[index].locked else { return }
        sets[index].name = builtIn.name
        sets[index].symbol = builtIn.symbol
        sets[index].apps = builtIn.apps()
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
        ensureBuiltInSets()
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
