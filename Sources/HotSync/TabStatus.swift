import Foundation
import PalmSync
import HotSyncCore
import Observation

/// Was ein Tab gerade tut und wie seine letzte Sitzung ausging - für die
/// Anzeige. Die Steuerung liegt in AppState.
@Observable
final class TabStatus {

    enum Phase: Equatable {
        case idle
        /// Start gedrückt (oder Kettenschritt), der Anschluss ist noch belegt
        case waitingForPort
        case listening(since: Date)
        /// vor den Installationen: die Sicherung geht auf den Palm zurück
        case restoring(user: PalmUser, file: String?, done: Int, total: Int)
        case syncing(user: PalmUser, file: String?, done: Int, total: Int)
        /// nach den Installationen: die Datenbanken im RAM werden gesichert;
        /// `done` von `total` sind durch (geholt oder unverändert)
        case backingUp(user: PalmUser, file: String?, done: Int, total: Int)
        /// nach der Sicherung: eine abgeglichene Datenbank wird vom Palm
        /// gelesen und geprüft
        case readingCalendar(user: PalmUser, database: String, done: Int)
        /// zum Schluss: das ROM wird ausgelesen, `done` von `total` Bytes
        case dumpingROM(user: PalmUser, done: Int, total: Int)
    }

    /// Ergebnis des ROM-Auslesens im letzten HotSync
    enum ROMDump: Equatable {
        case saved(file: String, bytes: Int)
        /// Palm OS 5: geht über HotSync nicht
        case unsupported(version: String)
        case failed(message: String)
    }

    /// Ergebnis der Sicherung im letzten HotSync
    struct Backup: Equatable {
        /// neu oder geändert geholt
        let saved: Int
        let unchanged: Int
        let failed: Int
        /// alle Datenbanken durch (nicht abgebrochen)
        let complete: Bool
    }

    /// Ergebnis des Zurückspielens im letzten HotSync
    struct Restore: Equatable {
        let installed: Int
        let failed: Int
        let total: Int
    }

    enum Result: Equatable {
        case finished(date: Date, installed: Int, failed: Int)
        /// kein Palm innerhalb der Wartezeit (Kettenschritt)
        case timedOut(date: Date)
        case failed(date: Date, message: String)
        /// ein Palm meldete sich, gehört aber nicht zu diesem Tab
        case rejected(date: Date, Rejection)
        case stopped(date: Date)
    }

    enum Rejection: Equatable {
        /// gehört zu einem anderen Profil
        case wrongPalm(found: PalmUser, owner: UUID)
        /// kein Profil kennt ihn
        case unknown(PalmUser)
    }

    var phase: Phase = .idle
    var lastResult: Result?
    var lastBackup: Backup?
    var lastRestore: Restore?
    var lastROMDump: ROMDump?
    let log = LiveLog(capacity: 200)

    var isBusy: Bool {
        if case .idle = phase { return false }
        return true
    }

    var isSyncing: Bool {
        switch phase {
        case .restoring, .syncing, .backingUp, .readingCalendar, .dumpingROM: return true
        default: return false
        }
    }
}

/// Etwas an einem Anschluss, das keinem Tab gehört: ein Palm, den ein
/// automatischer Listener angenommen, aber keinem Tab zuordnen konnte, oder
/// ein Fehler des Listeners. Wird oben im Fenster angezeigt, bis der
/// Benutzer es erledigt oder verwirft.
struct PortNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        /// kein Profil mit Tab an diesem Anschluss kennt ihn
        case unknown(PalmUser)
        /// Palm ohne Benutzer - welches Profil er werden soll, ist offen
        case blank
        /// der Listener ist gescheitert, bevor ein Palm erkannt war
        case failed(String)
    }

    let id = UUID()
    let port: String
    let kind: Kind
    let date: Date
}

/// Konflikte eines Abgleichs, die der Benutzer entscheidet, während der Palm
/// in der Sitzung wartet.
struct ConflictPrompt: Identifiable, Equatable {
    let id = UUID()
    /// Kalender, Kontakte oder Aufgaben
    let what: String
    let palmName: String
    let conflicts: [SyncConflict]
    let sessionToken: Int
}

/// Ein Palm, den HotSync noch nicht kennt: Der Dialog fragt, ob er ein neues
/// Gerät mit eigenem Tab werden soll.
struct NewPalmPrompt: Identifiable, Equatable {
    let id = UUID()
    let port: String
    /// Wer sich gemeldet hat. Ohne User-ID (`isBlank`) fragt der Dialog nach
    /// einem Namen - vorbelegt mit dem, den der Palm schon trägt.
    let user: PalmUser
    /// Die Sitzung, in der der Palm noch verbunden ist und auf die Antwort
    /// wartet; nil, wenn die Verbindung schon zu ist (nur bei einem Palm mit
    /// Benutzer - der ist an seiner ID auch beim nächsten HotSync eindeutig).
    let sessionToken: Int?
}
