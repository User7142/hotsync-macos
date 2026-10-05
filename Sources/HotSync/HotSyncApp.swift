import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        killOrphanedSessions()
        appState.onAttentionNeeded = { [weak self] in self?.showMainWindow() }
        appState.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
        killOrphanedSessions()
    }

    /// Ein hotsync-session aus einer abgestürzten Sitzung hielte den
    /// Anschluss (USB oder seriell) besetzt.
    private func killOrphanedSessions() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-9", "-x", "hotsync-session"]
        try? task.run()
        task.waitUntilExit()
    }

    /// .prc/.pdb per Doppelklick: in die Warteschlange des gewählten Tabs
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let id = appState.selectedTabId,
              let tab = appState.tabStore.tab(id),
              let queue = appState.queue(for: tab) else { return }
        queue.add(urls)
    }

    /// Dock-Icon geklickt → Fenster zeigen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "HotSync" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct HotSyncApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hauptfenster
        Window("HotSync", id: "main") {
            Group {
                if appDelegate.appState.showSetup {
                    SetupView()
                } else {
                    MainView()
                }
            }
            .environment(appDelegate.appState)
        }
        .defaultSize(width: 620, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu-Bar als Status-Indikator
        MenuBarExtra {
            Text(menuBarStatusText)
            Divider()
            Button(L10n.menuShowWindow) {
                appDelegate.showMainWindow()
            }
            .keyboardShortcut("1", modifiers: .command)
            Divider()
            Button(L10n.menuQuit) {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private var appState: AppState { appDelegate.appState }

    private var menuBarIcon: String {
        if appState.syncingTab != nil { return "arrow.triangle.2.circlepath.circle.fill" }
        if !appState.notices.isEmpty { return "exclamationmark.triangle" }
        if appState.isListening { return "antenna.radiowaves.left.and.right.circle" }
        return "arrow.triangle.2.circlepath"
    }

    private var menuBarStatusText: String {
        if let tab = appState.syncingTab { return L10n.menuBarSyncingTab(appState.title(of: tab)) }
        if !appState.notices.isEmpty { return L10n.menuBarUnknownPalm }
        if appState.isListening { return L10n.menuBarWaiting }
        return L10n.menuBarReady
    }
}
