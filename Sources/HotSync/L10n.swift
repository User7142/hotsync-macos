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

    // MARK: - SetupView

    static var welcomeTitle: String { s("Willkommen bei HotSync", "Welcome to HotSync") }
    static var welcomeSubtitle: String { s(
        "Richte dein erstes Palm-Gerät ein, um Dateien\nzu synchronisieren und Backups zu erstellen.",
        "Set up your first Palm device to sync files\nand create backups."
    ) }
    static var setupDevice: String { s("Gerät einrichten", "Set Up Device") }
    static var setupNameHint: String { s(
        "Dieser Name wird beim nächsten HotSync\nautomatisch auf den Palm übertragen.",
        "This name will be automatically transferred\nto the Palm on the next HotSync."
    ) }
    static var deviceNameLabel: String { s("Gerätename", "Device Name") }
    static var deviceNamePlaceholder: String { s("z.B. Palm m515", "e.g. Palm m515") }
    static var done: String { s("Fertig", "Done") }
    static var back: String { s("Zurück", "Back") }

    // MARK: - MainView Status

    static var statusSettingUsername: String { s("Username wird gesetzt...", "Setting username...") }
    static var statusReady: String { s("Bereit", "Ready") }
    static var statusSyncing: String { s("Synchronisiere...", "Syncing...") }
    static var statusWaiting: String { s("Warte auf Palm...", "Waiting for Palm...") }
    static var statusFinished: String { s("Sync abgeschlossen!", "Sync complete!") }
    static func statusError(_ msg: String) -> String { s("Fehler: \(msg)", "Error: \(msg)") }
    static func statusFilesReady(_ n: Int) -> String { s("\(n) Datei(en) bereit", "\(n) file(s) ready") }

    // MARK: - MainView Detail

    static var detailSettingUsername: String { s("Drücke HotSync auf dem Palm!", "Press HotSync on the Palm!") }
    static var detailListening: String { s("Lauscht auf Palm-Verbindung", "Listening for Palm connection") }
    static func detailSyncing(_ i: Int, _ n: Int) -> String { s("Datei \(i) von \(n)", "File \(i) of \(n)") }
    static var detailWaiting: String { s("Drücke HotSync auf dem Palm", "Press HotSync on the Palm") }
    static func detailFinished(_ n: Int) -> String { s("\(n) Datei(en) installiert", "\(n) file(s) installed") }
    static var detailError: String { s("Erneut versuchen oder Log prüfen", "Retry or check the log") }
    static var detailIdleEmpty: String { s(".prc/.pdb-Dateien hinzufügen oder HotSync drücken", "Add .prc/.pdb files or press HotSync") }
    static var detailIdleFiles: String { s("Sync starten, dann HotSync auf Palm drücken", "Start sync, then press HotSync on Palm") }

    // MARK: - MainView Progress

    static var progressLabel: String { s("Fortschritt", "Progress") }
    static var progressSettingUsername: String { s("Palm-Username wird gesetzt — Drücke HotSync!", "Setting Palm username — Press HotSync!") }
    static var progressWaiting: String { s("Drücke jetzt HotSync auf dem Palm!", "Press HotSync on the Palm now!") }

    // MARK: - MainView Queue

    static var queueLabel: String { s("Warteschlange", "Queue") }
    static var queueEmpty: String { s(".prc/.pdb-Dateien hierher ziehen", "Drop .prc/.pdb files here") }
    static func queueFiles(_ n: Int) -> String { s("\(n) Dateien", "\(n) files") }
    static func queueFilesInvalid(_ n: Int, _ invalid: Int) -> String { s(
        "\(n) Dateien, \(invalid) nicht installierbar", "\(n) files, \(invalid) not installable"
    ) }
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
        case .kindMismatch(let expectedResource):
            return expectedResource
                ? s(".prc, enthält aber eine Record-Datenbank (.pdb)", ".prc, but holds a record database (.pdb)")
                : s("enthält eine Ressourcen-Datenbank (.prc)", "holds a resource database (.prc)")
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
        case .palmError(let code, _): return s("Palm-Fehler \(code)", "Palm error \(code)")
        case .other(let line): return line
        case .notConfirmed: return s("Übertragung nicht bestätigt (Verbindung getrennt?)",
                                     "transfer not confirmed (connection lost?)")
        }
    }

    // MARK: - MainView Installed

    static var installedLabel: String { s("Installiert", "Installed") }
    static var installedEmpty: String { s("Noch keine Syncs", "No syncs yet") }

    // MARK: - MainView Log

    static var logLabel: String { s("Live-Protokoll", "Live Log") }
    static var logCopy: String { s("Kopieren", "Copy") }
    static var logEmpty: String { s("Kein Protokoll", "No log entries") }

    // MARK: - MainView Buttons

    static var syncStart: String { s("Sync starten", "Start Sync") }
    static func syncStartN(_ n: Int) -> String { s("Sync starten (\(n))", "Start Sync (\(n))") }
    static var cancel: String { s("Abbrechen", "Cancel") }

    // MARK: - UsernameSheet

    static var usernameSheetTitle: String { s("Palm-Username einrichten", "Set Up Palm Username") }
    static var usernameSheetMessage: String { s(
        "Dieser Palm hat keinen Benutzernamen.\nBitte gib einen Namen ein, der auf dem Palm gespeichert wird.",
        "This Palm has no username.\nPlease enter a name to be stored on the Palm."
    ) }
    static var usernameSheetSet: String { s("Setzen", "Set") }

    // MARK: - DeviceListView

    static var manageDevices: String { s("Geräte verwalten", "Manage Devices") }
    static var newNameAction: String { s("Neuen Namen vergeben", "Assign New Name") }
    static var readFromPalmAction: String { s("Identität vom Palm lesen", "Read Identity from Palm") }
    static var newDevice: String { s("Neues Gerät", "New Device") }
    static var active: String { s("aktiv", "active") }
    static var activate: String { s("Aktivieren", "Activate") }
    static var setupNewDevice: String { s("Neues Gerät einrichten", "Set Up New Device") }
    static var username: String { s("Benutzername", "Username") }
    static var usernamePlaceholder: String { s("z.B. Mein Palm", "e.g. My Palm") }
    static var deviceNotePlaceholder: String { s("z.B. Palm m515", "e.g. Palm m515") }
    static var deviceNoteLabel: String { s("Geräte-Bezeichnung (optional)", "Device Label (optional)") }
    static var createProfileOnly: String { s("Nur Profil erstellen", "Create Profile Only") }
    static var setOnPalm: String { s("Auf Palm setzen", "Set on Palm") }
    static var waitingForPalm: String { s("Drücke HotSync auf dem Palm...", "Press HotSync on the Palm...") }
    static var readPalmTitle: String { s("Warte auf Palm...", "Waiting for Palm...") }
    static var readPalmSubtitle: String { s(
        "Drücke den HotSync-Knopf\nauf dem Palm oder der Docking-Station.",
        "Press the HotSync button\non the Palm or docking station."
    ) }
    static var readPalmIdentityTitle: String { s("Identität vom Palm lesen", "Read Identity from Palm") }
    static var readPalmIdentitySubtitle: String { s(
        "Die aktuelle Benutzer-Identität wird\nvom Palm gelesen (benötigt HotSync).",
        "The current user identity will be read\nfrom the Palm (requires HotSync)."
    ) }
    static var readPalmButton: String { s("Palm lesen", "Read Palm") }
    static var deleteDevice: String { s("Gerät löschen?", "Delete Device?") }
    static func deleteMessage(_ name: String) -> String { s(
        "Das Profil \"\(name)\" und alle zugehörigen Dateien werden gelöscht.",
        "The profile \"\(name)\" and all associated files will be deleted."
    ) }
    static var delete: String { s("Löschen", "Delete") }
    static var connectionFailed: String { s("Verbindung fehlgeschlagen.", "Connection failed.") }
    static var noUsernameFound: String { s("Kein Benutzername gefunden. Palm verbunden?", "No username found. Is the Palm connected?") }

    // MARK: - DeviceSelectorView

    static var manageDevicesMenu: String { s("Geräte verwalten...", "Manage Devices...") }
    static var noDevice: String { s("Kein Gerät", "No Device") }

    // MARK: - HotSyncApp / MenuBar

    static var syncCompleteNotifTitle: String { s("HotSync abgeschlossen", "HotSync Complete") }
    static func syncCompleteNotifBody(_ n: Int) -> String { s("\(n) Datei(en) installiert", "\(n) file(s) installed") }
    static var menuShowWindow: String { s("Fenster zeigen", "Show Window") }
    static var menuQuit: String { s("HotSync beenden", "Quit HotSync") }
    static func menuBarSyncing(_ i: Int, _ n: Int) -> String { s("Synchronisiere \(i)/\(n)...", "Syncing \(i)/\(n)...") }
    static var menuBarWaiting: String { s("Warte auf Palm...", "Waiting for Palm...") }
    static var menuBarFinished: String { s("Sync abgeschlossen!", "Sync complete!") }
    static func menuBarError(_ msg: String) -> String { s("Fehler: \(msg)", "Error: \(msg)") }
    static func menuBarFilesReady(_ n: Int) -> String { s("\(n) Datei(en) bereit", "\(n) file(s) ready") }
    static var menuBarReady: String { s("Bereit", "Ready") }

    // MARK: - SyncEngine Logs

    static var logPilotXferNotFound: String { s("pilot-xfer nicht gefunden!", "pilot-xfer not found!") }
    static var logWaitingForConnection: String { s("Warte auf Palm-Verbindung...", "Waiting for Palm connection...") }
    static var logPilotXferListStarted: String { s("pilot-xfer -l gestartet, wartet auf USB...", "pilot-xfer -l started, waiting for USB...") }
    static var logConnectionSuccess: String { s("Palm-Verbindung erfolgreich", "Palm connection successful") }
    static var logTimeout: String { s("Timeout — kein Palm verbunden", "Timeout — no Palm connected") }
    static var logSyncComplete: String { s("HotSync abgeschlossen", "HotSync complete") }
    static var logCancelled: String { s("Abgebrochen", "Cancelled") }
    static func logFilesReady(_ n: Int) -> String { s(
        "\(n) Datei(en) bereit — Drücke HotSync auf dem Palm!",
        "\(n) file(s) ready — Press HotSync on the Palm!"
    ) }
    static func logAllInstalled(_ n: Int) -> String { s("Alle \(n) Datei(en) installiert!", "All \(n) file(s) installed!") }
    static func logFileProgress(_ i: Int, _ n: Int, _ name: String) -> String { "[\(i)/\(n)] \(name)" }
    static func logFileInstalled(_ name: String) -> String { s("\(name) installiert!", "\(name) installed!") }
    static func logFileNotInstalled(_ name: String, _ reason: String) -> String { s(
        "\(name) NICHT installiert (\(reason)) — bleibt für den nächsten HotSync in der Warteschlange",
        "\(name) NOT installed (\(reason)) — stays queued for the next HotSync"
    ) }
    static func logInstalledPartially(_ ok: Int, _ n: Int) -> String { s(
        "\(ok) von \(n) Datei(en) installiert",
        "\(ok) of \(n) file(s) installed"
    ) }
    static func logExitCode(_ code: Int32, _ name: String) -> String { s("Exit \(code) bei \(name)", "Exit \(code) for \(name)") }
    static var logErrorPilotXfer: String { s("FEHLER: pilot-xfer nicht in Bundle oder PATH!", "ERROR: pilot-xfer not found in bundle or PATH!") }
    static func logError(_ msg: String) -> String { s("FEHLER: \(msg)", "ERROR: \(msg)") }
    static var logPilotXferStarted: String { s("pilot-xfer gestartet, wartet auf USB...", "pilot-xfer started, waiting for USB...") }

    // MARK: - PalmIdentity Logs

    static var logPilotInstallNotFound: String { s("pilot-install-user nicht gefunden!", "pilot-install-user not found!") }
    static var logStartingPilotInstall: String { s("Starte pilot-install-user -l", "Starting pilot-install-user -l") }
    static var logPilotInstallRunning: String { s("pilot-install-user läuft, wartet auf USB...", "pilot-install-user running, waiting for USB...") }
    static var logNoOutput: String { s("Kein Output erhalten", "No output received") }
    static var logPilotInstallCancelled: String { s("pilot-install-user abgebrochen", "pilot-install-user cancelled") }
    static func logSetError(_ err: String) -> String { s("Fehler beim Setzen: \(err)", "Error setting username: \(err)") }
    static func logStartError(_ err: String) -> String { s("Fehler beim Starten: \(err)", "Error starting process: \(err)") }
    static var logPilotInstallStarted: String { s("pilot-install-user gestartet, wartet auf USB...", "pilot-install-user started, waiting for USB...") }

    // MARK: - DeviceManager Logs

    static func logProfileCreated(_ name: String, _ dir: String) -> String { s("Profil erstellt: '\(name)' → \(dir)/", "Profile created: '\(name)' → \(dir)/") }
    static func logProfileDeleted(_ name: String) -> String { s("Profil gelöscht: '\(name)'", "Profile deleted: '\(name)'") }
    static func logActiveProfile(_ name: String) -> String { s("Aktives Profil: '\(name)'", "Active profile: '\(name)'") }
    static func logLoadError(_ err: String) -> String { s("Fehler beim Laden von profiles.json: \(err)", "Error loading profiles.json: \(err)") }
    static func logSaveError(_ err: String) -> String { s("Fehler beim Speichern von profiles.json: \(err)", "Error saving profiles.json: \(err)") }
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

    // MARK: - DebugLog

    static var logAppStarted: String { s("=== HotSync gestartet ===", "=== HotSync started ===") }

    // MARK: - AppState Logs

    static var logSetupStarted: String { s("AppState.setup() gestartet", "AppState.setup() started") }
    static var logNoProfile: String { s("Kein Profil vorhanden → Setup-Wizard", "No profile found → Setup wizard") }
    static var logNoActiveProfile: String { s("Kein aktives Profil!", "No active profile!") }
    static func logActivatingProfile(_ name: String, _ dir: String) -> String { s("Aktiviere Profil: '\(name)' (\(dir)/)", "Activating profile: '\(name)' (\(dir)/)") }
    static var logFilesDetected: String { s("Dateien erkannt → Idle-Listener wird neu gestartet", "Files detected → Restarting idle listener") }
    static func logStartListening(_ n: Int) -> String { s("startListening() aufgerufen (files: \(n))", "startListening() called (files: \(n))") }
    static var logFileWatcherChange: String { s("FileWatcher: Änderung erkannt", "FileWatcher: Change detected") }
}
