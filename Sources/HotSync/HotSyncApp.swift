import SwiftUI
import AppKit

// Globaler App-State, damit AppDelegate und Views darauf zugreifen können
@Observable
final class AppState {
    let installQueue = InstallQueue()
    let syncEngine = SyncEngine()
    let palmIdentity = PalmIdentity()
    let deviceManager = DeviceManager()
    var fileWatcher: FileWatcher?

    // Setup-Steuerung
    var showSetup = false
    var showDeviceList = false

    // Username-Dialog (für Rename-Flow, nicht mehr Ersteinrichtung)
    var isSettingUsername = false

    // Sprachumschaltung
    var language: Language = L10n.language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            L10n.language = language
        }
    }

    func setup() {
        DebugLog.shared.log(L10n.logSetupStarted, source: "App")

        // Legacy-Migration
        deviceManager.migrateFromLegacy()

        // Prüfe ob Profile existieren
        if !deviceManager.hasProfiles {
            showSetup = true
            DebugLog.shared.log(L10n.logNoProfile, source: "App")
            return
        }

        // Aktives Profil laden und Pfade setzen
        activateCurrentProfile()
    }

    /// Aktiviert das aktuelle Profil: Pfade setzen, FileWatcher starten.
    func activateCurrentProfile() {
        guard let profile = deviceManager.activeProfile else {
            DebugLog.shared.log(L10n.logNoActiveProfile, source: "App")
            return
        }

        DebugLog.shared.log(L10n.logActivatingProfile(profile.username, profile.directoryName), source: "App")

        // Palm-Name anzeigen
        palmIdentity.currentPalmName = profile.username

        // InstallQueue auf Profil-Verzeichnisse umschalten
        let installDir = deviceManager.installDirectory(for: profile)
        let installedDir = deviceManager.installedDirectory(for: profile)
        installQueue.switchToProfile(installDir: installDir, installedDir: installedDir)

        // FileWatcher neu starten
        restartFileWatcher()

        // Sofort prüfen ob Dateien bereit sind
        rescanInstallFolder()
        DebugLog.shared.log("Pending files: \(installQueue.pendingFiles.count)", source: "App")
        startListeningIfReady()
    }

    /// Wechselt zu einem anderen Profil.
    func switchProfile(_ profile: DeviceProfile) {
        guard profile.id != deviceManager.activeProfileId else { return }

        // Laufenden Sync abbrechen
        if syncEngine.isActive {
            syncEngine.cancelSync()
        }

        deviceManager.setActiveProfile(profile)
        activateCurrentProfile()
    }

    /// Setup abgeschlossen — von SetupView aufgerufen.
    func setupCompleted() {
        showSetup = false
        activateCurrentProfile()
    }

    /// Automatischer Trigger: wird von FileWatcher und nach Sync-Abschluss aufgerufen.
    /// Startet Auto-Listen wenn nicht bereits aktiv. Wenn Dateien dazukommen
    /// während Idle-Listening läuft, wird der Listener neu gestartet.
    func startListeningIfReady() {
        guard !isSettingUsername else { return }

        // Wenn gerade Idle-Listening (ohne Dateien) und jetzt Dateien da sind:
        // Abbrechen und mit Dateien neu starten
        if syncEngine.isIdleListening && !installQueue.pendingFiles.isEmpty {
            DebugLog.shared.log(L10n.logFilesDetected, source: "App")
            syncEngine.cancelSync(silent: true)
            // Kurz warten bis cancelSync durchgelaufen ist
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.startListening()
            }
            return
        }

        // Bereits aktiv (File-Sync läuft) → nichts tun
        guard !syncEngine.isActive else { return }

        startListening()
    }

    /// Manueller/automatischer Sync-Start. Immer erlaubt.
    func startListening() {
        DebugLog.shared.log(L10n.logStartListening(installQueue.pendingFiles.count), source: "App")
        startFileInstall()
    }

    private func startFileInstall() {
        syncEngine.autoListen(
            queue: installQueue,
            palmIdentity: palmIdentity,
            onComplete: { [weak self] in
                guard let self else { return }
                let count = self.syncEngine.lastSyncedCount

                // Nur Notification wenn tatsächlich Dateien installiert wurden
                if count > 0 {
                    NotificationManager.shared.send(
                        title: L10n.syncCompleteNotifTitle,
                        body: L10n.syncCompleteNotifBody(count)
                    )
                }

                // lastSyncAt aktualisieren
                if let profileId = self.deviceManager.activeProfileId {
                    self.deviceManager.updateLastSync(for: profileId)
                }

                // Nach Abschluss: rescan und Auto-Listen neu starten
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    self?.rescanInstallFolder()
                    self?.startListeningIfReady()
                }
            }
        )
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "HotSync" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func rescanInstallFolder() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: installQueue.installDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let prcFiles = files.filter { InstallQueue.supportedExtensions.contains($0.pathExtension.lowercased()) }
        for file in prcFiles {
            installQueue.enqueue(file)
        }
    }

    private func restartFileWatcher() {
        fileWatcher?.stop()
        fileWatcher = nil

        let watcher = FileWatcher(path: installQueue.installDir.path)
        watcher.start { [weak self] in
            DebugLog.shared.log(L10n.logFileWatcherChange, source: "App")
            self?.rescanInstallFolder()
            self?.startListeningIfReady()
        }
        fileWatcher = watcher
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        killOrphanedPilotProcesses()
        appState.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.syncEngine.cancelSync()
        killOrphanedPilotProcesses()
    }

    /// Killt verwaiste pilot-xfer/pilot-install-user Prozesse von früheren Sitzungen.
    private func killOrphanedPilotProcesses() {
        for name in ["pilot-xfer", "pilot-install-user"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-9", "-f", name]
            try? task.run()
            task.waitUntilExit()
        }
    }

    /// Wird aufgerufen wenn .prc-Dateien per Doppelklick geöffnet werden
    func application(_ application: NSApplication, open urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            guard InstallQueue.supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let dest = appState.installQueue.installDir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            do {
                try fm.copyItem(at: url, to: dest)
                appState.installQueue.enqueue(dest)
            } catch {
                appState.installQueue.enqueue(url)
            }
        }
        appState.startListeningIfReady()
    }

    /// Dock-Icon geklickt → Fenster zeigen
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState.showMainWindow()
        }
        return true
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
        .defaultSize(width: 520, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu-Bar als Status-Indikator
        MenuBarExtra {
            Text(menuBarStatusText)
            Divider()
            Button(L10n.menuShowWindow) {
                appDelegate.appState.showMainWindow()
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

    private var menuBarIcon: String {
        switch appDelegate.appState.syncEngine.state {
        case .syncing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .listening:
            return "antenna.radiowaves.left.and.right.circle"
        case .finished:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle"
        case .idle:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var menuBarStatusText: String {
        switch appDelegate.appState.syncEngine.state {
        case .syncing:
            return L10n.menuBarSyncing(appDelegate.appState.syncEngine.currentFileIndex + 1, appDelegate.appState.syncEngine.totalFiles)
        case .listening:
            return L10n.menuBarWaiting
        case .finished:
            return L10n.menuBarFinished
        case .error(let msg):
            return L10n.menuBarError(msg)
        case .idle:
            let count = appDelegate.appState.installQueue.pendingFiles.count
            return count > 0 ? L10n.menuBarFilesReady(count) : L10n.menuBarReady
        }
    }
}
