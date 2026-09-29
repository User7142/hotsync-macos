import Foundation
import Observation

@Observable
final class DeviceManager {

    private(set) var profiles: [DeviceProfile] = []
    var activeProfileId: UUID? {
        didSet { UserDefaults.standard.set(activeProfileId?.uuidString, forKey: "activeProfileId") }
    }

    var activeProfile: DeviceProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    var hasProfiles: Bool { !profiles.isEmpty }

    private let baseDir: URL
    private let profilesFileURL: URL
    private let fm = FileManager.default

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDir = home.appendingPathComponent("HotSync")
        self.profilesFileURL = baseDir.appendingPathComponent("profiles.json")
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        loadProfiles()
    }

    // MARK: - CRUD

    @discardableResult
    func addProfile(username: String, userId: UInt, deviceNote: String?) -> DeviceProfile {
        // Prüfe ob directoryName-Kollision
        var profile = DeviceProfile(username: username, userId: userId, deviceNote: deviceNote)
        profile = resolveDirectoryCollision(profile)
        profiles.append(profile)
        ensureProfileDirectories(profile)
        saveProfiles()

        // Erstes Profil wird automatisch aktiv
        if profiles.count == 1 {
            activeProfileId = profile.id
        }

        DebugLog.shared.log(L10n.logProfileCreated(profile.username, profile.directoryName), source: "Device")
        return profile
    }

    func deleteProfile(_ profile: DeviceProfile) {
        profiles.removeAll { $0.id == profile.id }

        // Profil-Ordner löschen
        let dir = profileDirectory(for: profile)
        try? fm.removeItem(at: dir)

        // Falls aktives Profil gelöscht: auf erstes wechseln
        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
        }

        saveProfiles()
        DebugLog.shared.log(L10n.logProfileDeleted(profile.username), source: "Device")
    }

    func updateProfile(_ profile: DeviceProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        saveProfiles()
    }

    func updateLastSync(for profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].lastSyncAt = Date()
        saveProfiles()
    }

    func setActiveProfile(_ profile: DeviceProfile) {
        activeProfileId = profile.id
        DebugLog.shared.log(L10n.logActiveProfile(profile.username), source: "Device")
    }

    // MARK: - Verzeichnisse

    func profileDirectory(for profile: DeviceProfile) -> URL {
        baseDir.appendingPathComponent(profile.directoryName)
    }

    func installDirectory(for profile: DeviceProfile) -> URL {
        profileDirectory(for: profile).appendingPathComponent("Install")
    }

    func installedDirectory(for profile: DeviceProfile) -> URL {
        profileDirectory(for: profile).appendingPathComponent("Installed")
    }

    func backupsDirectory(for profile: DeviceProfile) -> URL {
        profileDirectory(for: profile).appendingPathComponent("Backups")
    }

    func ensureProfileDirectories(_ profile: DeviceProfile) {
        try? fm.createDirectory(at: installDirectory(for: profile), withIntermediateDirectories: true)
        try? fm.createDirectory(at: installedDirectory(for: profile), withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupsDirectory(for: profile), withIntermediateDirectories: true)
    }

    // MARK: - Migration

    func migrateFromLegacy() {
        let defaults = UserDefaults.standard
        guard let legacyName = defaults.string(forKey: "palmUsername"),
              !legacyName.isEmpty,
              !defaults.bool(forKey: "legacyMigrated") else { return }

        DebugLog.shared.log(L10n.logMigrationFound(legacyName), source: "Device")

        // Profil erstellen
        let userId = UInt.random(in: 10000...99999)
        let profile = addProfile(username: legacyName, userId: userId, deviceNote: nil)
        activeProfileId = profile.id

        // Bestehende Dateien verschieben
        let legacyInstall = baseDir.appendingPathComponent("Install")
        let legacyInstalled = baseDir.appendingPathComponent("Installed")
        let newInstall = installDirectory(for: profile)
        let newInstalled = installedDirectory(for: profile)

        moveContents(from: legacyInstall, to: newInstall)
        moveContents(from: legacyInstalled, to: newInstalled)

        // Legacy-Ordner entfernen wenn leer
        removeDirIfEmpty(legacyInstall)
        removeDirIfEmpty(legacyInstalled)

        defaults.set(true, forKey: "legacyMigrated")
        DebugLog.shared.log(L10n.logMigrationDone(profile.directoryName), source: "Device")
    }

    // MARK: - Private

    private func loadProfiles() {
        guard fm.fileExists(atPath: profilesFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: profilesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profiles = try decoder.decode([DeviceProfile].self, from: data)
        } catch {
            DebugLog.shared.log(L10n.logLoadError("\(error)"), source: "Device")
        }

        // Aktives Profil aus UserDefaults laden
        if let idStr = UserDefaults.standard.string(forKey: "activeProfileId"),
           let id = UUID(uuidString: idStr),
           profiles.contains(where: { $0.id == id }) {
            activeProfileId = id
        } else {
            activeProfileId = profiles.first?.id
        }
    }

    private func saveProfiles() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: profilesFileURL, options: .atomic)
        } catch {
            DebugLog.shared.log(L10n.logSaveError("\(error)"), source: "Device")
        }
    }

    private func resolveDirectoryCollision(_ profile: DeviceProfile) -> DeviceProfile {
        var p = profile
        let existingNames = Set(profiles.map { $0.directoryName })
        var candidate = p.directoryName
        var counter = 2
        while existingNames.contains(candidate) {
            candidate = "\(p.directoryName) \(counter)"
            counter += 1
        }
        // Falls Kollision: deviceNote anpassen
        if candidate != p.directoryName {
            p.deviceNote = candidate
        }
        return p
    }

    private func moveContents(from source: URL, to dest: URL) {
        guard fm.fileExists(atPath: source.path) else { return }
        guard let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for file in files {
            let target = dest.appendingPathComponent(file.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: file, to: target)
        }
    }

    private func removeDirIfEmpty(_ url: URL) {
        if let contents = try? fm.contentsOfDirectory(atPath: url.path), contents.isEmpty {
            try? fm.removeItem(at: url)
        }
    }
}
