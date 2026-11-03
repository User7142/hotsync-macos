import Foundation
import HotSyncCore
import PalmSyncMac

struct DeviceProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String
    var userId: UInt
    let createdAt: Date
    var lastSyncAt: Date?
    var deviceNote: String?
    /// Ende der letzten vollständigen Sicherung
    var lastBackupAt: Date?
    /// Palm-OS-Version, wie der Palm sie beim letzten HotSync meldete
    var romVersion: UInt32?
    /// Kalender-Abgleich Mac → Palm: welche Kalender, wie weit; nil = nie eingerichtet
    var calendarSync: CalendarSyncSettings?
    /// Kontakte-Abgleich Mac → Palm: welche Konten; nil = nie eingerichtet
    var contactSync: ContactSyncSettings?
    /// Aufgaben-Abgleich Mac → Palm: welche Erinnerungslisten; nil = nie eingerichtet
    var taskSync: TaskSyncSettings?
    /// Probelauf für den ganzen HotSync: die Abgleiche (Kalender, Kontakte,
    /// Aufgaben, Uhr, Zeitzonen) schreiben auf keiner Seite etwas, nur ins
    /// Log, was sie tun würden. Sicherung und abgelegte Dateien laufen.
    var dryRun: Bool?
    /// Kalender in beide Richtungen: der Palm wird gelesen, Feld für Feld
    /// mit dem Mac zusammengeführt, beide Seiten geschrieben. Aus: der
    /// Kalender des Macs ersetzt den des Palms.
    var calendarTwoWay: Bool?

    /// Kontakte und Aufgaben ebenso in beide Richtungen.
    var contactTwoWay: Bool?
    var taskTwoWay: Bool?

    /// Viele Löschungen auf einmal beim nächsten Abgleich zulassen; wird
    /// nach dem HotSync, der sie gebraucht hat, wieder ausgeschaltet.
    var allowMassDelete: Bool?

    /// Die ID, unter der dieser Mac im Palm als letzter PC steht (lastSyncPC):
    /// eine je Profil, von allen Spiegeln geteilt - der Palm kennt nur eine.
    var syncPCID: UInt32?

    var isDryRun: Bool { dryRun ?? false }
    var isMassDeleteAllowed: Bool { allowMassDelete ?? false }
    var isCalendarTwoWay: Bool { calendarTwoWay ?? false }
    var isContactTwoWay: Bool { contactTwoWay ?? false }
    var isTaskTwoWay: Bool { taskTwoWay ?? false }
    /// Die Uhr des Palms bei jedem HotSync vom Mac stellen; nil = aus
    var clockSync: Bool?
    /// Die Zeitzonen-Regeln der Orte des Palms aus der tzdata des Macs
    /// nachführen; nil = aus (ein Palm, dessen Orte umgeschrieben werden,
    /// braucht danach einen Soft-Reset)
    var zoneSync: Bool?

    /// Diesen Mac bei jedem Kabel-HotSync als primären PC für den
    /// Netzwerk-HotSync in den Palm schreiben; nil = aus
    var netSync: Bool?

    var isClockSyncOn: Bool { clockSync ?? false }
    var isZoneSyncOn: Bool { zoneSync ?? false }
    var isNetSyncOn: Bool { netSync ?? false }

    var palmOS: PalmOSVersion? { romVersion.map(PalmOSVersion.init(rom:)) }

    /// false, solange noch kein Palm diesem Profil zugeordnet ist (User-ID 0):
    /// Dann übernimmt der erste Palm ohne Benutzer, der in einem Tab dieses
    /// Profils synct, dessen Identität - oder der Benutzer ordnet einen
    /// bestehenden Palm zu.
    var isBound: Bool { userId != 0 }

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
