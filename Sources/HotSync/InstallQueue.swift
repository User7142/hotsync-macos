import Foundation
import Observation
import HotSyncCore

/// The queue is the Install folder of a profile: every file in it is shown -
/// dropped on the window, opened with HotSync or copied there in the
/// Finder - together with what will happen to it. Every profile has its own
/// queue; its FileWatcher calls `refresh()` on every change of the folder.
@Observable
final class InstallQueue {

    enum Status: Equatable {
        /// valid Palm database, installed with the next HotSync
        case ready(PalmDatabaseFile)
        /// not a Palm database HotSync can install - never sent
        case invalid(PalmDatabaseFile.Problem)
        /// part of the running HotSync session
        case installing(PalmDatabaseFile)
        /// the Palm refused it last time; tried again with the next HotSync
        case failed(PalmDatabaseFile, InstallFailure)

        var isInstallable: Bool {
            if case .invalid = self { return false }
            return true
        }
    }

    struct QueueItem: Identifiable {
        var id: URL { url }
        let url: URL
        let size: Int64
        let status: Status
        var name: String { url.lastPathComponent }
    }

    struct InstalledItem: Identifiable {
        let id = UUID()
        let name: String
        let date: Date
    }

    private(set) var items: [QueueItem] = []
    private(set) var installedItems: [InstalledItem] = []

    let installDir: URL
    let installedDir: URL

    /// Last failure per file name, valid as long as the file is unchanged.
    private var failures: [String: (failure: InstallFailure, modified: Date)] = [:]
    /// Files of the running session and the session they belong to.
    private var installing: Set<String> = []
    private var installingSession: Int?

    init(installDir: URL, installedDir: URL) {
        self.installDir = installDir
        self.installedDir = installedDir
        ensureDirectories()
        refresh()
    }

    /// Files the next HotSync sends: everything valid, including files that
    /// failed before.
    var pendingFiles: [URL] {
        items.filter { $0.status.isInstallable }.map(\.url)
    }

    var invalidCount: Int {
        items.filter { !$0.status.isInstallable }.count
    }

    /// Reads the Install folder again and checks every file.
    func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let files = (try? fm.contentsOfDirectory(
            at: installDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var result: [QueueItem] = []
        var seen: Set<String> = []
        for url in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            let modified = values?.contentModificationDate ?? .distantPast
            seen.insert(name)

            let status: Status
            switch PalmDatabaseFile.inspect(url: url) {
            case .failure(let problem):
                status = .invalid(problem)
            case .success(let database):
                if installing.contains(name) {
                    status = .installing(database)
                } else if let failure = failures[name], failure.modified == modified {
                    status = .failed(database, failure.failure)
                } else {
                    status = .ready(database)
                }
            }
            result.append(QueueItem(url: url, size: Int64(values?.fileSize ?? 0), status: status))
        }
        failures = failures.filter { seen.contains($0.key) }
        items = result
    }

    // MARK: - Session

    /// The files of a HotSync session: shown as "installing" until it ends.
    func beginInstall(_ urls: [URL], session: Int) {
        installing = Set(urls.map(\.lastPathComponent))
        installingSession = session
        refresh()
    }

    /// Ends a session: installed files move to Installed/, failed ones stay
    /// with their reason. Ignored if another session took over meanwhile.
    func finishInstall(session: Int, installed: Set<URL>, failed: [String: InstallFailure]) {
        guard installingSession == session else { return }
        for url in installed {
            markInstalled(url)
        }
        for (name, failure) in failed {
            let url = installDir.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            failures[name] = (failure, modified)
        }
        installing.removeAll()
        installingSession = nil
        refresh()
    }

    /// A session ended without a result (cancelled).
    func abortInstall(session: Int) {
        guard installingSession == session else { return }
        installing.removeAll()
        installingSession = nil
        refresh()
    }

    // MARK: - Files

    /// Copies files into the Install folder (drop, "Open with").
    func add(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            let dest = installDir.appendingPathComponent(url.lastPathComponent)
            guard url.standardizedFileURL != dest.standardizedFileURL else { continue }
            try? fm.removeItem(at: dest)
            do {
                try fm.copyItem(at: url, to: dest)
            } catch {
                DebugLog.shared.log(L10n.logCopyFailed(url.lastPathComponent, error.localizedDescription),
                                    source: "Queue")
            }
            failures[url.lastPathComponent] = nil
        }
        refresh()
    }

    /// Moves a queued file to the Trash.
    func remove(_ item: QueueItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            DebugLog.shared.log(L10n.logFileRemoved(item.name), source: "Queue")
        } catch {
            DebugLog.shared.log(L10n.logRemoveFailed(item.name, error.localizedDescription), source: "Queue")
        }
        failures[item.name] = nil
        refresh()
    }

    private func markInstalled(_ url: URL) {
        let fileName = url.lastPathComponent
        let dest = installedDir.appendingPathComponent(fileName)
        let fm = FileManager.default

        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: url, to: dest)
            DebugLog.shared.log(L10n.logFileMoved(fileName), source: "Queue")
        } catch {
            DebugLog.shared.log(L10n.logMoveFailed(error.localizedDescription), source: "Queue")
            // installed, so it must not be offered again
            try? fm.removeItem(at: url)
        }
        failures[fileName] = nil

        installedItems.insert(InstalledItem(name: fileName, date: Date()), at: 0)
        if installedItems.count > 50 {
            installedItems = Array(installedItems.prefix(50))
        }
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: installDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: installedDir, withIntermediateDirectories: true)
    }
}
