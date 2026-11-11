import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var store: DockStore

    var body: some View {
        if store.sets.isEmpty {
            Text("No dock sets yet")
        }

        ForEach(Array(store.sets.enumerated()), id: \.element.id) { index, set in
            let toggle = Toggle(isOn: Binding(
                get: { store.activeSetID == set.id },
                set: { _ in store.apply(set) }
            )) {
                Label(set.name.isEmpty ? "Untitled" : set.name, systemImage: set.symbol)
            }
            if index < 9 {
                toggle.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            } else {
                toggle
            }
        }

        Divider()

        Button("Edit Dock Sets…") {
            AppDelegate.shared?.showEditor()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("New Set from Current Dock") {
            store.addSetFromCurrentDock()
            AppDelegate.shared?.showEditor()
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { store.launchAtLogin },
            set: { enabled in
                LoginItem.setEnabled(enabled)
                store.launchAtLogin = LoginItem.isEnabled
            }
        ))

        Button("Quit Dock Morph") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
