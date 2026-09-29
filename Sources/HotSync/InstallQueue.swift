import Foundation
import Observation

@Observable
final class InstallQueue {

    struct InstalledItem: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
    }

    private(set) var pendingFiles: [URL] = []
    private(set) var installedItems: [InstalledItem] = []

    private(set) var installDir: URL
    private(set) var installedDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.installDir = home.appendingPathComponent("HotSync/Install")
        self.installedDir = home.appendingPathComponent("HotSync/Installed")
        ensureDirectories()
        scanExistingFiles()
    }

    /// Wechselt die Verzeichnisse auf ein bestimmtes Profil.
    func switchToProfile(installDir: URL, installedDir: URL) {
        // Bestehende Queue leeren
        pendingFiles.removeAll()
        installedItems.removeAll()

        self.installDir = installDir
        self.installedDir = installedDir
        ensureDirectories()
        scanExistingFiles()
    }

    static let supportedExtensions: Set<String> = ["prc", "pdb"]

    func enqueue(_ url: URL) {
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        if !pendingFiles.contains(url) {
            pendingFiles.append(url)
        }
    }

    func enqueueMultiple(_ urls: [URL]) {
        for url in urls {
            enqueue(url)
        }
    }

    func dequeueAll() -> [URL] {
        let files = pendingFiles
        pendingFiles.removeAll()
        return files
    }

    func markInstalled(_ url: URL) {
        let fileName = url.lastPathComponent
        let dest = installedDir.appendingPathComponent(fileName)
        let fm = FileManager.default

        // Falls FileWatcher die Datei während des Syncs erneut enqueued hat: bereinigen
        pendingFiles.removeAll { $0.lastPathComponent == fileName }

        // Verschiebe Datei nach Installed/
        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: url, to: dest)
            DebugLog.shared.log(L10n.logFileMoved(fileName), source: "Queue")
        } catch {
            DebugLog.shared.log(L10n.logMoveFailed(error.localizedDescription), source: "Queue")
            // Fallback: Datei aus Install/ löschen damit sie nicht erneut erkannt wird
            let installSource = installDir.appendingPathComponent(fileName)
            try? fm.removeItem(at: installSource)
        }

        installedItems.insert(
            InstalledItem(name: fileName, date: Date()),
            at: 0
        )

        // Maximal 50 Einträge im Log behalten
        if installedItems.count > 50 {
            installedItems = Array(installedItems.prefix(50))
        }
    }

    func removeFromQueue(_ url: URL) {
        pendingFiles.removeAll { $0 == url }
    }

    // MARK: - Private

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: installedDir, withIntermediateDirectories: true)
    }

    private func scanExistingFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: installDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where Self.supportedExtensions.contains(file.pathExtension.lowercased()) {
            pendingFiles.append(file)
        }
    }
}
