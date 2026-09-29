import Foundation

struct DeviceProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String
    var userId: UInt
    let createdAt: Date
    var lastSyncAt: Date?
    var deviceNote: String?

    /// Bereinigter Verzeichnisname basierend auf deviceNote oder username.
    var directoryName: String {
        let base = (deviceNote?.isEmpty == false) ? deviceNote! : username
        // Nur sichere Zeichen für Dateisysteme
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = base.unicodeScalars.filter { allowed.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Palm" : result
    }

    init(
        id: UUID = UUID(),
        username: String,
        userId: UInt,
        createdAt: Date = Date(),
        lastSyncAt: Date? = nil,
        deviceNote: String? = nil
    ) {
        self.id = id
        self.username = username
        self.userId = userId
        self.createdAt = createdAt
        self.lastSyncAt = lastSyncAt
        self.deviceNote = deviceNote
    }
}
