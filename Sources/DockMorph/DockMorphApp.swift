import AppKit
import ServiceManagement
import SwiftUI

@main
enum Main {
    static func main() {
        if let status = CommandLineInterface.run(Array(CommandLine.arguments.dropFirst())) {
            exit(status)
        }
        DockMorphApp.main()
    }
}

struct DockMorphApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DockStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
        } label: {
            Image(systemName: store.activeSet?.symbol ?? "dock.rectangle")
        }
    }
}

/// Dock Morph lives in the menu bar; it only appears in the Dock while the editor window is open.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) static var shared: AppDelegate?
    private var editorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Pick up changes made by `DockMorph --apply` from the command line.
        DistributedNotificationCenter.default().addObserver(
            forName: DockStore.changedNotification, object: nil, queue: .main
        ) { _ in
            DockStore.shared.load()
        }

        // Show the window whenever the app is opened by hand; stay quiet when started at login.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if DockStore.shared.isFirstRun || !launchedAtLogin {
            showEditor()
        }
    }

    /// Opening the app again while it is already running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showEditor()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showEditor() {
        if editorWindow == nil {
            let root = EditorView().environmentObject(DockStore.shared)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Dock Morph"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 500))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("DockMorphEditor")
            editorWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DockStore.shared.lastError = "Couldn't change the login item: \(error.localizedDescription)"
            AppDelegate.shared?.showEditor()
        }
    }
}
