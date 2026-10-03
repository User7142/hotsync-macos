import Foundation
import HotSyncCore
import Observation

enum Language: String, CaseIterable {
    case de, en

    var displayName: String {
        switch self {
        case .de: "Deutsch"
        case .en: "English"
        }
    }

    static var systemDefault: Language {
        Locale.preferredLanguages.first?.hasPrefix("de") == true ? .de : .en
    }
}

/// Die Anzeigesprache als beobachtbarer Zustand: Jede View, die einen
/// L10n-Text liest, liest damit auch die Sprache und wird beim Umschalten
/// neu gezeichnet - ohne dass die Views die Sprache selbst abfragen müssen.
@Observable
final class LanguageSetting: @unchecked Sendable {
    static let shared = LanguageSetting()

    var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = Language(rawValue: saved) {
            language = lang
        } else {
            language = .systemDefault
        }
    }
}

enum L10n {
    static var language: Language {
        get { LanguageSetting.shared.language }
        set { LanguageSetting.shared.language = newValue }
    }

    private static func s(_ de: String, _ en: String) -> String {
        language == .de ? de : en
    }

    // MARK: - Allgemein

    static var done: String { s("Fertig", "Done") }
    static var back: String { s("Zurück", "Back") }
    static var cancel: String { s("Abbrechen", "Cancel") }
    static var save: String { s("Sichern", "Save") }
    static var delete: String { s("Löschen", "Delete") }

    /// "m515 (ID 41981)"
    static func identity(_ name: String, _ userId: UInt32) -> String {
        let shown = name.isEmpty ? s("ohne Namen", "no name") : name
        return "\(shown) (ID \(userId))"
    }
    static func identityUnbound(_ name: String) -> String { s(
        "\(name) (noch keinem Palm zugeordnet)", "\(name) (no Palm assigned yet)"
    ) }

    // MARK: - SetupView

    static var welcomeTitle: String { s("Willkommen bei HotSync", "Welcome to HotSync") }
    static var welcomeSubtitle: String { s(
        "Richte dein erstes Palm-Gerät ein, um Dateien\nzu synchronisieren und Backups zu erstellen.",
        "Set up your first Palm device to sync files\nand create backups."
    ) }
    static var setupDevice: String { s("Gerät einrichten", "Set Up Device") }
    static var setupNameHint: String { s(
        "Ein neuer Palm ohne Benutzer übernimmt diesen Namen\nbeim ersten HotSync. Ein schon benutzter Palm\nlässt sich zuordnen, wenn er sich meldet.",
        "A new Palm without a user takes this name\non its first HotSync. A Palm that is already in use\ncan be assigned when it connects."
    ) }
    static var deviceNameLabel: String { s("Gerätename", "Device Name") }
    static var deviceNamePlaceholder: String { s("z.B. Palm m515", "e.g. Palm m515") }

    // MARK: - Warteschlange

    static var queueLabel: String { s("Warteschlange", "Queue") }
    static var queueEmpty: String { s(".prc/.pdb-Dateien hierher ziehen", "Drop .prc/.pdb files here") }
    static func queueFiles(_ n: Int) -> String {
        n == 1 ? s("1 Datei", "1 file") : s("\(n) Dateien", "\(n) files")
    }
    static func queueFilesInvalid(_ n: Int, _ invalid: Int) -> String {
        "\(queueFiles(n)), " + s("\(invalid) nicht installierbar", "\(invalid) not installable")
    }
    static var queueRemoveHelp: String { s("In den Papierkorb legen", "Move to Trash") }
    static var queueReady: String { s("Bereit – wird beim nächsten HotSync installiert",
                                      "Ready – installed with the next HotSync") }
    static var queueInstalling: String { s("Wird übertragen …", "Transferring …") }
    static var queueWaiting: String { s("Wartet auf HotSync", "Waiting for HotSync") }
    static func queueFailed(_ reason: String) -> String { s(
        "Nicht installiert: \(reason) – wird beim nächsten HotSync erneut versucht",
        "Not installed: \(reason) – tried again with the next HotSync"
    ) }
    static func queueInvalid(_ reason: String) -> String { s(
        "Wird nicht übertragen: \(reason)", "Not sent: \(reason)"
    ) }
    static func queueDatabase(_ name: String, _ version: String?, _ type: String,
                              _ creator: String, _ size: String) -> String {
        let title = version.map { "\(name) \($0)" } ?? name
        return "\(title) · \(type)/\(creator) · \(size)"
    }

    static func problemText(_ problem: PalmDatabaseFile.Problem) -> String {
        switch problem {
        case .unsupportedExtension(let ext):
            return ext.isEmpty
                ? s("keine Palm-Datei (.prc, .pdb, .pqa)", "not a Palm file (.prc, .pdb, .pqa)")
                : s("keine Palm-Datei (.\(ext))", "not a Palm file (.\(ext))")
        case .unreadable: return s("Datei nicht lesbar", "file cannot be read")
        case .tooSmall: return s("zu klein für eine Palm-Datenbank", "too small for a Palm database")
        case .invalidName: return s("ungültiger Datenbankname im Header", "invalid database name in the header")
        case .truncated: return s("unvollständig (abgeschnitten)", "incomplete (truncated)")
        }
    }

    static func failureText(_ failure: InstallFailure) -> String {
        switch failure {
        case .protectedOnPalm:
            return s("auf dem Palm geschützt oder in Benutzung (z. B. eine aktive Erweiterung wie DateFix: dort erst ausschalten)",
                     "protected or in use on the Palm (e.g. an active extension such as DateFix: turn it off there first)")
        case .openOnPalm: return s("auf dem Palm geöffnet – App dort schließen", "open on the Palm – close the app there")
        case .readOnly: return s("auf dem Palm schreibgeschützt (ROM)", "read-only on the Palm (ROM)")
        case .notEnoughSpace: return s("nicht genug Speicher auf dem Palm", "not enough memory on the Palm")
        case .tooLarge: return s("zu groß für den Palm", "too large for the Palm")
        case .unreadableFile: return s("Datei auf dem Mac nicht lesbar", "file cannot be read on the Mac")
        case .palmError(let code): return s("Palm-Fehler \(code)", "Palm error \(code)")
        case .notConfirmed: return s("Übertragung nicht bestätigt (Verbindung getrennt?)",
                                     "transfer not confirmed (connection lost?)")
        }
    }

    // MARK: - Installiert, Log

    static var installedLabel: String { s("Installiert", "Installed") }
    static var installedEmpty: String { s("Noch keine Syncs", "No syncs yet") }
    static var logLabel: String { s("Live-Protokoll", "Live Log") }
    static var logCopy: String { s("Kopieren", "Copy") }
    static var logEmpty: String { s("Kein Protokoll", "No log entries") }

    // MARK: - Kopfzeile, Tabs

    static var chainsButton: String { s("Ketten", "Chains") }
    static var devicesButton: String { s("Geräte", "Devices") }
    static var tabsEmpty: String { s("Noch kein Tab – ein Tab ist ein Palm an einem Anschluss.",
                                     "No tab yet – a tab is a Palm on a port.") }
    static var tabAdd: String { s("Tab anlegen", "Add Tab") }
    static var tabAddHelp: String { s("Neuer Tab: Palm + Anschluss", "New tab: Palm + port") }
    static var tabEditHelp: String { s("Tab bearbeiten", "Edit tab") }
    static var tabSyncNow: String { s("Jetzt syncen", "Sync Now") }
    static var tabSyncNowHelp: String { s(
        "Lauscht gezielt für diesen Palm – ein anderer Palm bekommt nichts installiert",
        "Listens for this Palm only – any other Palm gets nothing installed"
    ) }
    static var tabStop: String { s("Stopp", "Stop") }
    static var tabNewTitle: String { s("Neuer Tab", "New Tab") }
    static var tabEditTitle: String { s("Tab bearbeiten", "Edit Tab") }
    static var tabProfile: String { s("Palm", "Palm") }
    static var tabPort: String { s("Anschluss", "Port") }
    static func tabPortMissing(_ name: String) -> String { s("\(name) (nicht verbunden)", "\(name) (not connected)") }
    static var tabBaudRate: String { s("Baudrate", "Baud rate") }
    static var tabAutoListen: String { s("Automatisch lauschen", "Listen automatically") }
    static var tabAutoListenHint: String { s(
        "Der Anschluss wartet ständig auf einen Palm und gibt ihn dem Tab, zu dem er gehört. Ohne: nur per „Jetzt syncen“ oder als Schritt einer Kette.",
        "The port waits for a Palm all the time and hands it to the tab it belongs to. Without: only with “Sync Now” or as a step of a chain."
    ) }
    static func tabDuplicate(_ title: String) -> String { s(
        "Diesen Palm gibt es an diesem Anschluss schon: \(title)",
        "This Palm already has a tab on this port: \(title)"
    ) }
    static var tabDelete: String { s("Tab löschen", "Delete Tab") }
    static var tabDeleteConfirm: String { s("Tab löschen?", "Delete Tab?") }
    static var tabDeleteMessage: String { s(
        "Der Tab verschwindet auch aus allen Ketten. Profil und Warteschlange bleiben.",
        "The tab is also removed from all chains. Profile and queue stay."
    ) }

    // MARK: - Zustand eines Tabs

    static var phaseIdleAuto: String { s("Bereit – lauscht, sobald der Anschluss frei ist",
                                         "Ready – listens as soon as the port is free") }
    static var phaseIdleManual: String { s("Bereit – „Jetzt syncen“ oder als Kettenschritt",
                                           "Ready – “Sync Now” or as a chain step") }
    static var phaseListeningAuto: String { s("Lauscht – HotSync auf dem Palm drücken",
                                              "Listening – press HotSync on the Palm") }
    static var phaseListeningTargeted: String { s("Wartet gezielt auf diesen Palm – HotSync drücken",
                                                  "Waiting for this Palm – press HotSync") }
    static var phaseWaitingForPort: String { s("Wartet, bis der Anschluss frei ist",
                                               "Waiting for the port to become free") }
    static var phasePortMissing: String { s("Anschluss nicht verbunden", "Port not connected") }
    static func phaseSyncing(_ name: String, _ done: Int, _ total: Int, _ file: String?) -> String {
        let current = file.map { " – \($0)" } ?? ""
        return s("\(name): \(done) von \(total) Datei(en)\(current)", "\(name): \(done) of \(total) file(s)\(current)")
    }
    static func phaseSyncingNothing(_ name: String) -> String { s(
        "\(name) verbunden – nichts zu installieren", "\(name) connected – nothing to install"
    ) }

    // MARK: - Anschlüsse

    static func portConnectedAt(_ time: String) -> String { s("Kabel verbunden um \(time)", "cable connected at \(time)") }
    static var portConnectedBeforeLaunch: String { s("schon beim Start verbunden", "connected before launch") }
    static var portNotConnected: String { s("nicht verbunden", "not connected") }
    static func portLastSeen(_ name: String, _ time: String) -> String { s(
        "zuletzt gemeldet: \(name) um \(time)", "last seen: \(name) at \(time)"
    ) }

    // MARK: - Ergebnis einer Sitzung

    static func resultFinished(_ time: String, _ installed: Int, _ failed: Int) -> String {
        failed == 0
            ? s("\(time): \(installed) Datei(en) installiert", "\(time): \(installed) file(s) installed")
            : s("\(time): \(installed) installiert, \(failed) nicht – siehe Warteschlange",
                "\(time): \(installed) installed, \(failed) not – see the queue")
    }
    static func resultTimedOut(_ time: String) -> String { s(
        "\(time): Kein Palm hat sich gemeldet", "\(time): No Palm connected"
    ) }
    static func resultFailed(_ time: String, _ message: String) -> String { s(
        "\(time): Fehler – \(message)", "\(time): Error – \(message)"
    ) }
    static func resultStopped(_ time: String) -> String { s("\(time): Gestoppt", "\(time): Stopped") }
    static func resultWrongPalm(_ time: String, _ found: String, _ owner: String, _ expected: String) -> String { s(
        "\(time): Gemeldet hat sich \(found) – das ist der Palm von „\(owner)“, erwartet war \(expected). Nichts installiert.",
        "\(time): \(found) connected – that is the Palm of “\(owner)”, expected \(expected). Nothing installed."
    ) }
    static func resultUnknownPalm(_ time: String, _ found: String, _ expected: String) -> String { s(
        "\(time): Gemeldet hat sich \(found), erwartet war \(expected). Kein Profil kennt diesen Palm – nichts installiert.",
        "\(time): \(found) connected, expected \(expected). No profile knows this Palm – nothing installed."
    ) }
    static func assignThisProfile(_ name: String) -> String { s(
        "Diesen Palm „\(name)“ zuordnen", "Assign this Palm to “\(name)”"
    ) }
    static var assignHint: String { s(
        "Nach dem Zuordnen HotSync auf dem Palm noch einmal drücken.",
        "After assigning, press HotSync on the Palm once more."
    ) }
    static var createProfileFromPalm: String { s("Neues Profil für diesen Palm", "New profile for this Palm") }

    // MARK: - Hinweise (Palm ohne Tab)

    static func noticeUnknownPalm(_ name: String, _ userId: UInt32) -> String { s(
        "Unbekannter Palm: \(identity(name, userId)) – nichts installiert",
        "Unknown Palm: \(identity(name, userId)) – nothing installed"
    ) }
    static var noticeBlankPalm: String { s(
        "Ein Palm ohne Benutzer hat sich gemeldet – im Tab seines Profils „Jetzt syncen“ wählen, dann HotSync drücken",
        "A Palm without a user connected – choose “Sync Now” in its profile's tab, then press HotSync"
    ) }
    static func noticeDetail(_ port: String, _ time: String) -> String { s("\(port) um \(time)", "\(port) at \(time)") }
    static var assignToProfile: String { s("Zuordnen zu …", "Assign to …") }

    // MARK: - Ketten

    static var chainsTitle: String { s("Ketten", "Chains") }
    static var chainsEmpty: String { s(
        "Eine Kette synct Tabs nacheinander:\nwenn A fertig ist, B, dann C.",
        "A chain syncs tabs one after another:\nwhen A is done, B, then C."
    ) }
    static var chainNew: String { s("Neue Kette", "New Chain") }
    static func chainDefaultName(_ n: Int) -> String { s("Kette \(n)", "Chain \(n)") }
    static var chainRun: String { s("Starten", "Run") }
    static var chainNoSteps: String { s("keine Schritte", "no steps") }
    static var chainName: String { s("Name", "Name") }
    static var chainSteps: String { s("Schritte (in dieser Reihenfolge)", "Steps (in this order)") }
    static var chainAddStep: String { s("Schritt hinzufügen", "Add Step") }
    static var chainHint: String { s(
        "Jeder Schritt wartet bis zu 5 Minuten auf seinen Palm. Scheitert ein Schritt, hält die Kette an: wiederholen, überspringen oder abbrechen.",
        "Each step waits up to 5 minutes for its Palm. If a step fails, the chain pauses: retry, skip or cancel."
    ) }
    static func chainBannerTitle(_ name: String, _ step: Int, _ total: Int) -> String { s(
        "Kette „\(name)“ – Schritt \(step) von \(total)", "Chain “\(name)” – step \(step) of \(total)"
    ) }
    static func chainRunningDetail(_ tab: String) -> String { s(
        "\(tab): HotSync auf diesem Palm drücken", "\(tab): press HotSync on this Palm"
    ) }
    static func chainPausedDetail(_ tab: String, _ reason: String) -> String { s(
        "Angehalten bei \(tab): \(reason)", "Paused at \(tab): \(reason)"
    ) }
    static var chainRetry: String { s("Wiederholen", "Retry") }
    static var chainSkip: String { s("Überspringen", "Skip") }
    static var chainCancel: String { s("Kette abbrechen", "Cancel Chain") }
    static var chainStepStopped: String { s("gestoppt", "stopped") }
    static var chainStepMissingTab: String { s("Tab gibt es nicht mehr", "tab no longer exists") }
    static func chainReasonTimeout(_ minutes: Int) -> String { s(
        "kein Palm innerhalb von \(minutes) Minuten", "no Palm within \(minutes) minutes"
    ) }
    static func chainReasonFilesFailed(_ n: Int) -> String { s(
        "\(n) Datei(en) nicht installiert", "\(n) file(s) not installed"
    ) }
    static func chainReasonWrongPalm(_ name: String) -> String { s(
        "falscher Palm (\(name))", "wrong Palm (\(name))"
    ) }
    static var chainFinishedTitle: String { s("Kette fertig", "Chain finished") }
    static func chainFinishedBody(_ name: String, _ skipped: Int) -> String {
        skipped == 0
            ? s("„\(name)“ ist durchgelaufen", "“\(name)” has run through")
            : s("„\(name)“ ist durch, \(skipped) Schritt(e) übersprungen",
                "“\(name)” is done, \(skipped) step(s) skipped")
    }

    // MARK: - Geräte

    static var manageDevices: String { s("Geräte verwalten", "Manage Devices") }
    static var newDevice: String { s("Neues Gerät", "New Device") }
    static var setupNewDevice: String { s("Neues Gerät einrichten", "Set Up New Device") }
    static var username: String { s("Benutzername", "Username") }
    static var usernamePlaceholder: String { s("z.B. Mein Palm", "e.g. My Palm") }
    static var deviceNotePlaceholder: String { s("z.B. Palm m515", "e.g. Palm m515") }
    static var deviceNoteLabel: String { s("Geräte-Bezeichnung (optional)", "Device Label (optional)") }
    static var createProfile: String { s("Anlegen", "Create") }
    static var addProfileHint: String { s(
        "Es entsteht ein USB-Tab. Ein neuer Palm ohne Benutzer übernimmt den Namen beim ersten HotSync; einen schon benutzten Palm ordnest du zu, wenn er sich meldet.",
        "A USB tab is created. A new Palm without a user takes the name on its first HotSync; a Palm already in use is assigned when it connects."
    ) }
    static func profileUserId(_ id: UInt) -> String { "ID \(id)" }
    static var profileUnbound: String { s("noch keinem Palm zugeordnet", "no Palm assigned yet") }
    static var deleteDevice: String { s("Gerät löschen?", "Delete Device?") }
    static func deleteMessage(_ name: String) -> String { s(
        "Das Profil \"\(name)\", seine Tabs und alle zugehörigen Dateien werden gelöscht.",
        "The profile \"\(name)\", its tabs and all associated files will be deleted."
    ) }

    // MARK: - Mitteilungen, Menüleiste

    static var syncCompleteNotifTitle: String { s("HotSync abgeschlossen", "HotSync Complete") }
    static func syncCompleteNotifBody(_ n: Int) -> String { s("\(n) Datei(en) installiert", "\(n) file(s) installed") }
    static var menuShowWindow: String { s("Fenster zeigen", "Show Window") }
    static var menuQuit: String { s("HotSync beenden", "Quit HotSync") }
    static func menuBarSyncingTab(_ title: String) -> String { s("Synchronisiere \(title) …", "Syncing \(title) …") }
    static var menuBarUnknownPalm: String { s("Unbekannter Palm – siehe Fenster", "Unknown Palm – see window") }
    static var menuBarWaiting: String { s("Warte auf Palm...", "Waiting for Palm...") }
    static var menuBarReady: String { s("Bereit", "Ready") }

    // MARK: - Einträge im HotSync-Log des Palms

    static func palmLogSummary(_ installed: Int, _ failed: Int) -> String {
        failed == 0
            ? s("HotSync für macOS: \(installed) Datei(en) installiert", "HotSync for macOS: \(installed) file(s) installed")
            : s("HotSync für macOS: \(installed) installiert, \(failed) nicht",
                "HotSync for macOS: \(installed) installed, \(failed) not")
    }
    static var palmLogNothingInstalled: String { s(
        "HotSync für macOS: Palm nicht zugeordnet, nichts installiert",
        "HotSync for macOS: Palm not assigned, nothing installed"
    ) }

    // MARK: - Sitzungs-Logs

    static func logTabListening(_ port: String) -> String { s("Lauscht an \(port)", "Listening on \(port)") }
    static func logPalmConnected(_ name: String, _ userId: UInt32, _ files: Int) -> String { s(
        "Palm verbunden: \(identity(name, userId)) – \(files) Datei(en) zu installieren",
        "Palm connected: \(identity(name, userId)) – \(files) file(s) to install"
    ) }
    static func logPalmRejected(_ name: String, _ userId: UInt32) -> String { s(
        "Palm \(identity(name, userId)) gehört nicht hierher – nichts installiert",
        "Palm \(identity(name, userId)) does not belong here – nothing installed"
    ) }
    static func logAdopting(_ name: String) -> String { s(
        "Palm ohne Benutzer übernimmt das Profil „\(name)“", "Palm without a user takes the profile “\(name)”"
    ) }
    static func logInstalling(_ name: String) -> String { s("Installiere \(name) …", "Installing \(name) …") }
    static func logFileInstalled(_ name: String) -> String { s("\(name) installiert", "\(name) installed") }
    static func logFileNotInstalled(_ name: String, _ reason: String) -> String { s(
        "\(name) NICHT installiert (\(reason)) — bleibt für den nächsten HotSync in der Warteschlange",
        "\(name) NOT installed (\(reason)) — stays queued for the next HotSync"
    ) }
    static func logSessionError(_ port: String, _ stage: String, _ message: String) -> String { s(
        "Fehler an \(port) (\(stage)): \(message)", "Error on \(port) (\(stage)): \(message)"
    ) }
    static func logSessionBrokenLine(_ line: String) -> String { s(
        "Unerwartete Ausgabe von hotsync-session: \(line)", "Unexpected output from hotsync-session: \(line)"
    ) }
    static func logSessionWriteFailed(_ err: String) -> String { s(
        "Anweisung an hotsync-session nicht zugestellt: \(err)", "Could not send command to hotsync-session: \(err)"
    ) }
    static func sessionToolMissing(_ err: String) -> String { s(
        "hotsync-session nicht startbar: \(err)", "hotsync-session cannot be started: \(err)"
    ) }
    static func sessionExitStatus(_ status: Int) -> String { s(
        "hotsync-session endete mit Status \(status)", "hotsync-session ended with status \(status)"
    ) }
    static func logSerialConnected(_ name: String) -> String { s("Serieller Adapter verbunden: \(name)", "Serial adapter connected: \(name)") }
    static func logSerialDisconnected(_ name: String) -> String { s("Serieller Adapter getrennt: \(name)", "Serial adapter disconnected: \(name)") }
    static func logChainStarted(_ name: String) -> String { s("Kette „\(name)“ gestartet", "Chain “\(name)” started") }
    static func logChainFinished(_ name: String) -> String { s("Kette „\(name)“ fertig", "Chain “\(name)” finished") }
    static func logChainCancelled(_ name: String) -> String { s("Kette „\(name)“ abgebrochen", "Chain “\(name)” cancelled") }
    static func logTabsMigrated(_ n: Int) -> String { s(
        "\(n) Tab(s) aus den bisherigen Profilen angelegt (USB, automatisch lauschen)",
        "Created \(n) tab(s) from the existing profiles (USB, listen automatically)"
    ) }

    // MARK: - DeviceManager Logs

    static func logProfileCreated(_ name: String, _ dir: String) -> String { s("Profil erstellt: '\(name)' → \(dir)/", "Profile created: '\(name)' → \(dir)/") }
    static func logProfileDeleted(_ name: String) -> String { s("Profil gelöscht: '\(name)'", "Profile deleted: '\(name)'") }
    static func logIdentityAssigned(_ name: String, _ userId: UInt32) -> String { s(
        "Palm zugeordnet: \(identity(name, userId))", "Palm assigned: \(identity(name, userId))"
    ) }
    static func logLoadError(_ err: String) -> String { s("Fehler beim Laden: \(err)", "Error loading: \(err)") }
    static func logSaveError(_ err: String) -> String { s("Fehler beim Speichern: \(err)", "Error saving: \(err)") }
    static func logMigrationFound(_ name: String) -> String { s("Legacy-Migration: '\(name)' gefunden", "Legacy migration: '\(name)' found") }
    static func logMigrationDone(_ dir: String) -> String { s("Legacy-Migration abgeschlossen → \(dir)/", "Legacy migration complete → \(dir)/") }

    // MARK: - InstallQueue Logs

    static func logFileMoved(_ name: String) -> String { s("Verschoben: \(name) → Installed/", "Moved: \(name) → Installed/") }
    static func logMoveFailed(_ err: String) -> String { s("Move fehlgeschlagen: \(err)", "Move failed: \(err)") }
    static func logFileRemoved(_ name: String) -> String { s("In den Papierkorb: \(name)", "Moved to Trash: \(name)") }
    static func logRemoveFailed(_ name: String, _ err: String) -> String { s(
        "\(name) konnte nicht entfernt werden: \(err)", "Could not remove \(name): \(err)"
    ) }
    static func logCopyFailed(_ name: String, _ err: String) -> String { s(
        "\(name) konnte nicht in den Install-Ordner kopiert werden: \(err)",
        "Could not copy \(name) to the Install folder: \(err)"
    ) }

    // MARK: - DebugLog, AppState

    static var logAppStarted: String { s("=== HotSync gestartet ===", "=== HotSync started ===") }
    static var logSetupStarted: String { s("AppState.setup() gestartet", "AppState.setup() started") }
}
