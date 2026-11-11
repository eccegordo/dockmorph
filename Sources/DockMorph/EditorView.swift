import AppKit
import SwiftUI
import UniformTypeIdentifiers

// View state lives in small ObservableObjects rather than @State: with only the Command Line
// Tools installed (no Xcode), the SDK's @State macro plugin isn't available.
final class EditorState: ObservableObject {
    @Published var selection: DockSet.ID?
}

final class SetDetailState: ObservableObject {
    @Published var selectedApps = Set<String>()
    @Published var confirmReplace = false
}

/// The main window: dock sets on the left, the selected set's apps on the right.
struct EditorView: View {
    @EnvironmentObject private var store: DockStore
    @StateObject private var ui = EditorState()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 420)
        .onAppear {
            // `-selectSet "<name>"` on the command line opens the window on that set (used for screenshots).
            if let name = UserDefaults.standard.string(forKey: "selectSet"),
               let set = store.sets.first(where: { $0.name == name }), ui.selection == nil {
                ui.selection = set.id
            }
            if ui.selection == nil { ui.selection = store.activeSetID ?? store.sets.first?.id }
        }
        .alert("Dock Morph", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $ui.selection) {
                ForEach(store.sets) { set in
                    HStack {
                        Image(systemName: set.symbol)
                            .frame(width: 22)
                        Text(set.name.isEmpty ? "Untitled" : set.name)
                            .lineLimit(1)
                        Spacer()
                        if set.locked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Locked")
                        }
                        if set.id == store.activeSetID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .help("In the Dock now")
                        }
                    }
                    .tag(set.id)
                    .contextMenu {
                        Button("Switch Dock to This Set") { store.apply(set) }
                        Button("Duplicate") {
                            ui.selection = store.addSet(name: "\(set.name) Copy", apps: set.apps).id
                        }
                        Divider()
                        Button(set.locked ? "Unlock" : "Lock") { store.setLocked(!set.locked, for: set.id) }
                        if set.builtIn != nil {
                            Button("Revert to Default") { store.revertToDefault(set.id) }
                                .disabled(set.locked || !store.isModified(set))
                        }
                        Divider()
                        Button("Delete", role: .destructive) { delete(set.id) }
                            .disabled(!store.canRemove(set))
                    }
                }
                .onMove { store.sets.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 12) {
                Menu {
                    Button("Empty Set") { ui.selection = store.addSet().id }
                    Button("From Current Dock") { ui.selection = store.addSetFromCurrentDock().id }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a dock set")

                Button {
                    if let id = ui.selection { delete(id) }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(!(store.sets.first { $0.id == ui.selection }.map(store.canRemove) ?? false))
                .help("Delete the selected dock set (built-in and locked sets can't be deleted)")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = ui.selection, let set = binding(for: id) {
            SetDetailView(set: set)
                .id(id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Select a dock set, or add one with +")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for id: UUID) -> Binding<DockSet>? {
        guard let fallback = store.sets.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.sets.first { $0.id == id } ?? fallback },
            set: { updated in
                if let index = store.sets.firstIndex(where: { $0.id == id }) {
                    store.sets[index] = updated
                }
            }
        )
    }

    private func delete(_ id: UUID) {
        store.remove(id)
        if ui.selection == id, !store.sets.contains(where: { $0.id == id }) {
            ui.selection = store.sets.first?.id
        }
    }
}

/// Edits one dock set: name, menu bar icon and the ordered list of apps.
struct SetDetailView: View {
    @EnvironmentObject private var store: DockStore
    @Binding var set: DockSet
    @StateObject private var ui = SetDetailState()

    private static let symbols: [(symbol: String, title: String)] = [
        ("dock.rectangle", "Dock"),
        ("apple.logo", "macOS"),
        ("paintbrush", "Creative"),
        ("globe", "Browsing"),
        ("book", "Research"),
        ("chevron.left.forwardslash.chevron.right", "Development"),
        ("terminal", "Terminal"),
        ("pencil.and.ruler", "Design"),
        ("camera", "Photo"),
        ("film", "Video"),
        ("music.note", "Music"),
        ("envelope", "Communication"),
        ("briefcase", "Work"),
        ("chart.bar", "Data"),
        ("gamecontroller", "Games"),
        ("house", "Home"),
        ("star", "Favorites"),
    ]

    private var isActive: Bool { store.activeSetID == set.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if set.apps.isEmpty {
                emptyState
            } else {
                appList
            }
            Divider()
            footer
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !set.locked else { return false }
            add(urls)
            return true
        }
        .confirmationDialog("Replace this set's apps with the apps in the Dock right now?",
                            isPresented: $ui.confirmReplace) {
            Button("Replace", role: .destructive) { set.apps = DockController.currentAppPaths() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Self.symbols, id: \.symbol) { item in
                    Button {
                        set.symbol = item.symbol
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                    }
                }
            } label: {
                Image(systemName: set.symbol)
                    .frame(width: 22)
            }
            .fixedSize()
            .disabled(set.locked)
            .help("Menu bar icon for this set")

            TextField("Set name", text: $set.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .disabled(set.locked)

            Button {
                set.locked.toggle()
            } label: {
                Image(systemName: set.locked ? "lock.fill" : "lock.open")
                    .frame(width: 18)
            }
            .help(set.locked ? "Locked — click to allow changes to this set"
                             : "Lock this set so it can't be changed or deleted")

            Button(isActive ? "Update Dock" : "Switch Dock to This Set") {
                store.apply(set)
            }
            .buttonStyle(.borderedProminent)
            .help("Put these apps in the Dock (restarts the Dock)")
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.dashed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No apps in this set")
                .font(.headline)
            Text(set.locked ? "Unlock this set to add apps." : "Click Add Apps, or drag apps here from Finder.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appList: some View {
        List(selection: $ui.selectedApps) {
            ForEach(set.apps, id: \.self) { path in
                AppRow(path: path)
                    .tag(path)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        Button("Remove from Set", role: .destructive) {
                            set.apps.removeAll { $0 == path }
                        }
                        .disabled(set.locked)
                    }
            }
            .onMove(perform: set.locked ? nil : { set.apps.move(fromOffsets: $0, toOffset: $1) })
            .onDelete(perform: set.locked ? nil : { set.apps.remove(atOffsets: $0) })
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onDeleteCommand(perform: removeSelected)
    }

    private var footer: some View {
        HStack {
            Button("Add Apps…", action: chooseApps)
                .disabled(set.locked)
            Button("Remove", action: removeSelected)
                .disabled(set.locked || ui.selectedApps.isEmpty)
            Spacer()
            Text((set.apps.count == 1 ? "1 app" : "\(set.apps.count) apps") + (set.locked ? " · Locked" : ""))
                .foregroundStyle(.secondary)
            Spacer()
            if set.builtIn != nil {
                Button("Revert") { store.revertToDefault(set.id) }
                    .fixedSize()
                    .disabled(set.locked || !store.isModified(set))
                    .help("Restore this built-in set's original name, icon and apps")
            }
            Button("Use Current Dock") {
                if set.apps.isEmpty {
                    set.apps = DockController.currentAppPaths()
                } else {
                    ui.confirmReplace = true
                }
            }
            .fixedSize()
            .disabled(set.locked)
        }
        .padding(12)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to \(set.name)"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK {
            add(panel.urls)
        }
    }

    private func add(_ urls: [URL]) {
        for url in urls where url.pathExtension == "app" {
            let path = DockController.normalize(url.path)
            if !set.apps.contains(path) { set.apps.append(path) }
        }
    }

    private func removeSelected() {
        guard !set.locked else { return }
        set.apps.removeAll { ui.selectedApps.contains($0) }
        ui.selectedApps.removeAll()
    }
}

private struct AppRow: View {
    let path: String

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: path)
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(DockController.appName(path))
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !exists {
                Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("This app wasn't found and will be skipped when the set is applied")
            }
        }
        .padding(.vertical, 2)
    }
}
