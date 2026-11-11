import Foundation

/// Small command line interface so sets can be switched from scripts, Shortcuts or hotkey tools:
///   DockMorph --list            list the sets (the active one is starred)
///   DockMorph --apply <name>    switch the Dock to a set
///   DockMorph --current         print the apps pinned in the Dock right now
///   DockMorph --revert <name>   restore a built-in set to its default apps
enum CommandLineInterface {
    /// Returns an exit status when the arguments were a CLI command, nil to launch the app.
    static func run(_ arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "--list":
            let store = DockStore.shared
            for set in store.sets {
                let flags = [set.builtIn != nil ? "built-in" : nil, set.locked ? "locked" : nil].compactMap { $0 }
                let suffix = flags.isEmpty ? "" : " [" + flags.joined(separator: ", ") + "]"
                print("\(set.id == store.activeSetID ? "*" : " ") \(set.name) (\(set.apps.count) apps)\(suffix)")
            }
            return 0

        case "--current":
            DockController.currentAppPaths().forEach { print($0) }
            return 0

        case "--apply":
            let name = arguments.dropFirst().joined(separator: " ")
            let store = DockStore.shared
            guard let set = store.sets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                FileHandle.standardError.write(Data("No dock set named \"\(name)\". Try --list.\n".utf8))
                return 1
            }
            store.apply(set)
            if let error = store.lastError {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                return 1
            }
            DistributedNotificationCenter.default().postNotificationName(
                DockStore.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
            print("Dock switched to \(set.name)")
            return 0

        case "--revert":
            let name = arguments.dropFirst().joined(separator: " ")
            let store = DockStore.shared
            guard let set = store.sets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  set.builtIn != nil else {
                FileHandle.standardError.write(Data("No built-in dock set named \"\(name)\".\n".utf8))
                return 1
            }
            guard !set.locked else {
                FileHandle.standardError.write(Data("\(set.name) is locked. Unlock it in Dock Morph first.\n".utf8))
                return 1
            }
            store.revertToDefault(set.id)
            DistributedNotificationCenter.default().postNotificationName(
                DockStore.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
            print("Reverted \(set.name) to its default apps")
            return 0

        case "--help", "-h":
            print("""
            usage: DockMorph [--list | --apply <set name> | --current | --revert <set name>]
            With no arguments, starts the menu bar app.
            """)
            return 0

        default:
            return nil
        }
    }
}
