import Foundation
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
        case syncing(user: PalmUser, file: String?, done: Int, total: Int)
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
    let log = LiveLog(capacity: 200)

    var isBusy: Bool {
        if case .idle = phase { return false }
        return true
    }

    var isSyncing: Bool {
        if case .syncing = phase { return true }
        return false
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
