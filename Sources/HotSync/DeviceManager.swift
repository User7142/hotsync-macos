import Foundation
import HotSyncCore
import Observation

@Observable
final class DeviceManager {

    private(set) var profiles: [DeviceProfile] = []

    var hasProfiles: Bool { !profiles.isEmpty }

    func profile(_ id: UUID) -> DeviceProfile? {
        profiles.first { $0.id == id }
    }

    /// Die Profile, wie der Identitätsabgleich (PalmAdmission) sie braucht.
    var identities: [ProfileIdentity] {
        profiles.map { ProfileIdentity(id: $0.id, userId: UInt32(truncatingIfNeeded: $0.userId)) }
    }

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

        DebugLog.shared.log(L10n.logProfileCreated(profile.username, profile.directoryName), source: "Device")
        return profile
    }

    func deleteProfile(_ profile: DeviceProfile) {
        profiles.removeAll { $0.id == profile.id }

        // Profil-Ordner löschen
        let dir = profileDirectory(for: profile)
        try? fm.removeItem(at: dir)

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

    /// Bindet ein Profil an einen Palm: Name und User-ID kommen vom Palm.
    /// Ab dann erkennt HotSync diesen Palm an seiner User-ID.
    func assignIdentity(_ user: PalmUser, to profileId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].username = user.name
        profiles[index].userId = UInt(user.userId)
        saveProfiles()
        DebugLog.shared.log(L10n.logIdentityAssigned(user.name, user.userId), source: "Device")
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

        // Profil erstellen - die User-ID kommt beim ersten HotSync vom Palm
        let profile = addProfile(username: legacyName, userId: 0, deviceNote: nil)

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
