import Foundation
import HotSyncCore
import PalmSync
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
    static var queueMoveTo: String { s("Verschieben nach", "Move to") }
    static func queueMoveFilesTo(_ n: Int) -> String { s("\(n) Dateien verschieben nach", "Move \(n) files to") }
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

    /// Beim Zurückspielen ist eine geschützte oder geöffnete Datenbank fast
    /// immer eine, die der Palm während des HotSyncs selbst offen hält (Net
    /// Prefs) - nicht eine Erweiterung, die man ausschalten könnte.
    static func restoreFailureText(_ failure: InstallFailure) -> String {
        switch failure {
        case .protectedOnPalm, .openOnPalm:
            return s("vom Palm während des HotSyncs selbst benutzt – lässt sich dabei nicht ersetzen",
                     "in use by the Palm itself during the HotSync – cannot be replaced then")
        default:
            return failureText(failure)
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
    static func portNetworkInterface(_ name: String, _ ip: String) -> String { s("Netzwerk: \(name) (\(ip))", "Network: \(name) (\(ip))") }
    static var portNetworkAll: String { s("Netzwerk: alle Schnittstellen (nicht empfohlen)", "Network: all interfaces (not recommended)") }
    static func portNetworkHint(_ ip: String?, all: Bool) -> String {
        let address = ip ?? s("keine Adresse", "no address")
        let where_ = all
            ? s("Lauscht auf TCP-Port 14238 auf jeder Schnittstelle – auch Ethernet und VPN. Der Netzwerk-HotSync kennt kein Passwort: jeder im selben Netz, der die Benutzer-ID eines Palms kennt, kann sich als dieser melden. Besser nur das WLAN.",
                "Listens on TCP 14238 on every interface – Ethernet and VPN included. Network HotSync has no password: anyone on the same network who knows a Palm's user ID can connect as it. Better to pick the Wi-Fi alone.")
            : s("Lauscht auf TCP-Port 14238 nur auf dieser Schnittstelle, wie der HotSync-Manager (Netzwerk-HotSync); der Netzwerk-HotSync kennt kein Passwort, die Benutzer-ID des Palms ist die ganze Prüfung.",
                "Listens on TCP 14238 on this interface only, like HotSync Manager did (network HotSync); network HotSync has no password, the Palm's user ID is the whole check.")
        return where_ + s(
            " Auf dem Palm: HotSync › Menü › Modem-Sync-Einst. › Netzwerk, dann Menü › Primäres PC-Setup, Adresse dieses Macs: \(address). Beim ersten Mal fragt macOS, ob HotSync eingehende Verbindungen annehmen darf. Der erste HotSync eines Palms und jeder Abgleich in beide Richtungen nach einem Reset brauchen das Kabel.",
            " On the Palm: HotSync › menu › Modem Sync Prefs › Network, then menu › Primary PC Setup, this Mac's address: \(address). The first time, macOS asks whether HotSync may accept incoming connections. A Palm's first HotSync, and a two-way sync after a reset, need the cable."
        )
    }
    static var tabPortsHint: String { s(
        "Ein Palm kann einen Tab je Anschluss haben – etwa USB und WLAN; sie teilen Profil, Einstellungen und Spiegel.",
        "A Palm can have one tab per port – USB and Wi-Fi, say; they share the profile, its settings and the mirrors."
    ) }
    static var logNoAdoptOverNetwork: String { s(
        "Ein Palm ohne Benutzer hat sich über das Netz gemeldet: keine Identität vergeben – der erste HotSync eines Palms geht über das Kabel",
        "A Palm without a user connected over the network: no identity assigned – a Palm's first HotSync goes over the cable"
    ) }
    static func logTwoWayNetworkNeedsCable(_ what: String) -> String { s(
        "\(what): über das Netz nur für einen Palm, den dieser Mac zuletzt abgeglichen hat – erst ein HotSync am Kabel",
        "\(what): over the network only for a Palm this Mac synced last – one HotSync over the cable first"
    ) }
    static var logNetworkIdle: String { s(
        "Netzwerk: seit drei Minuten nichts vom Palm, Sitzung beendet", "Network: nothing from the Palm for three minutes, session ended"
    ) }
    static func portNetworkAddress(_ ip: String?) -> String {
        s("Adresse dieses Macs: \(ip ?? "–")", "this Mac's address: \(ip ?? "–")")
    }
    static var tabSyncMode: String { s("HotSync", "HotSync") }
    static var tabSyncModeHint: String { s(
        "„Abgleichen“ ist der Abgleich von Kalender, Kontakten, Aufgaben, Uhr und Zeitzonen, wie er für diesen Palm eingestellt ist; „Installieren“ die Warteschlange; „Sichern“ holt nach den Installationen die Datenbanken im RAM des Palms auf den Mac – beim ersten Mal alle, danach nur die geänderten. Für einen langsamen seriellen Tab kann „Nur installieren“ sinnvoll sein.",
        "“Sync” is the Calendar, Contacts, Tasks, clock and time-zone sync as set up for this Palm; “Install” the queue; “Back Up” fetches the Palm's RAM databases to the Mac after the installs – all of them the first time, then only the changed ones. For a slow serial tab, “Install Only” can make sense."
    ) }
    static func modeName(_ mode: HotSyncMode) -> String {
        switch mode {
        case .syncInstallBackup: return s("Abgleichen + Installieren + Sichern", "Sync + Install + Back Up")
        case .syncOnly: return s("Nur abgleichen", "Sync Only")
        case .installBackup: return s("Installieren + Sichern", "Install + Back Up")
        case .installOnly: return s("Nur installieren", "Install Only")
        }
    }
    static func allTabsMode(_ mode: HotSyncMode) -> String {
        s("Alle Tabs: \(modeName(mode))", "All Tabs: \(modeName(mode))")
    }
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
    static func phaseBackingUp(_ name: String, _ done: Int, _ total: Int, _ file: String?) -> String {
        let current = file.map { " – \($0)" } ?? ""
        return total == 0
            ? s("\(name): Sicherung wird vorbereitet …", "\(name): preparing the backup …")
            : s("\(name): Sicherung, \(done) von \(total) Datenbanken\(current)",
                "\(name): backup, \(done) of \(total) databases\(current)")
    }
    static func phaseRestoring(_ name: String, _ done: Int, _ total: Int, _ file: String?) -> String {
        let current = file.map { " – \($0)" } ?? ""
        return s("\(name): Sicherung wird zurückgespielt, \(done) von \(total)\(current)",
                 "\(name): restoring the backup, \(done) of \(total)\(current)")
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
    static func resultBackup(_ saved: Int, _ unchanged: Int, _ failed: Int, complete: Bool) -> String {
        let head = complete ? s("Gesichert", "Backed up") : s("Sicherung abgebrochen", "Backup cut short")
        let failedPart = failed == 0 ? "" : s(", \(failed) nicht lesbar – siehe Log", ", \(failed) unreadable – see the log")
        return s("\(head): \(saved) neu oder geändert, \(unchanged) unverändert\(failedPart)",
                 "\(head): \(saved) new or changed, \(unchanged) unchanged\(failedPart)")
    }
    static func resultRestore(_ installed: Int, _ failed: Int) -> String {
        failed == 0
            ? s("Sicherung zurückgespielt: \(installed) Datenbanken", "Backup restored: \(installed) databases")
            : s("Sicherung zurückgespielt: \(installed) Datenbanken, \(failed) nicht – siehe Log",
                "Backup restored: \(installed) databases, \(failed) not – see the log")
    }
    static var showInFinder: String { s("Im Finder zeigen", "Show in Finder") }
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
        "Palm ohne Benutzer – zum Anlegen HotSync auf dem Palm erneut drücken, oder im Tab seines Profils „Jetzt syncen“ wählen",
        "Palm without a user – press HotSync on the Palm again to add it, or choose “Sync Now” in its profile's tab"
    ) }
    static func noticeListenerFailed(_ message: String) -> String { s(
        "HotSync fehlgeschlagen: \(message)", "HotSync failed: \(message)"
    ) }
    static func newPalmTitle(_ port: String) -> String { s("Neuer Palm an \(port)", "New Palm on \(port)") }
    static func newPalmUnknown(_ name: String, _ userId: UInt32) -> String { s(
        "\(identity(name, userId)) ist HotSync noch nicht bekannt. Als neues Gerät anlegen? Es bekommt einen eigenen Tab und eine eigene Warteschlange – den Namen kannst du dabei ändern.",
        "HotSync does not know \(identity(name, userId)) yet. Add it as a new device? It gets its own tab and its own queue – you can change its name."
    ) }
    static var newPalmBlank: String { s(
        "Dieser Palm hat noch keinen Benutzernamen. Unter welchem Namen soll er angelegt werden?",
        "This Palm has no user name yet. Which name should it get?"
    ) }
    static var newPalmNamePlaceholder: String { s("Benutzername, z. B. Thomas LifeDrive", "User name, e.g. Thomas LifeDrive") }
    static var newPalmCreate: String { s("Als neues Gerät anlegen", "Add as New Device") }
    static var newPalmIgnore: String { s("Ignorieren", "Ignore") }
    static var newPalmAgainHint: String { s(
        "Danach HotSync auf dem Palm noch einmal drücken.",
        "Then press HotSync on the Palm once more."
    ) }
    static var newPalmWaitingHint: String { s(
        "Der Palm wartet, bis du hier antwortest – danach wird gleich installiert.",
        "The Palm waits for your answer here – its queue is installed right after."
    ) }
    static func newPalmExisting(_ name: String) -> String { s(
        "Es gibt schon ein Gerät „\(name)“ – für ein neues Gerät einen anderen Namen wählen.",
        "There is already a device “\(name)” – choose another name for a new device."
    ) }
    static var newPalmModeNew: String { s("Neues Gerät", "New Device") }
    static var newPalmModeExisting: String { s("Bekanntes Gerät übernehmen", "Take Over a Known Device") }
    static var newPalmDevice: String { s("Gerät:", "Device:") }
    static func newPalmDeviceWithBackup(_ name: String, _ count: Int) -> String { s(
        "\(name) – Sicherung mit \(count) Datenbanken", "\(name) – backup with \(count) databases"
    ) }
    static var newPalmSwitchToTakeOver: String { s("Übernehmen …", "Take Over …") }
    static func newPalmTakeOver(_ name: String) -> String { s("„\(name)“ übernehmen", "Take Over “\(name)”") }
    static var newPalmTakeOverHint: String { s(
        "Der Palm bekommt Name und ID des Geräts zurück – mit Tab, Warteschlange und Installiertem. Er wartet, bis du hier antwortest.",
        "The Palm gets the device's name and ID back – with its tab, queue and installed files. It waits for your answer here."
    ) }
    static var newPalmRenameHint: String { s(
        "Der Palm wartet, bis du hier antwortest. Der neue Name wird ihm gleich in diesem HotSync geschrieben, seine ID bleibt.",
        "The Palm waits for your answer here. The new name is written to it in this very HotSync; its ID stays."
    ) }
    static var newPalmBlankHint: String { s(
        "Der Palm wartet, bis du hier antwortest. Name und ID werden ihm gleich in diesem HotSync geschrieben.",
        "The Palm waits for your answer here. Name and ID are written to it in this very HotSync."
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
        "Das Profil \"\(name)\" und seine Tabs werden gelöscht. Sein Ordner – mit Warteschlange, Installiertem und Sicherung – kommt in den Papierkorb.",
        "The profile \"\(name)\" and its tabs will be deleted. Its folder – with the queue, installed files and backup – goes to the Trash."
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
    static func logBackupStarting(_ path: String) -> String { s(
        "Sicherung nach \(path) …", "Backup to \(path) …"
    ) }
    static func logBackedUp(_ name: String, _ bytes: Int) -> String { s(
        "\(name) gesichert (\(bytes) Bytes)", "\(name) backed up (\(bytes) bytes)"
    ) }
    static func logBackupFailed(_ name: String, _ palmOSError: Int) -> String { s(
        "\(name) NICHT gesichert (Palm-OS-Fehler \(palmOSError))",
        "\(name) NOT backed up (Palm OS error \(palmOSError))"
    ) }
    // MARK: - Kalender-Abgleich

    static var calendarSyncTitle: String { s("Kalender: Mac → Palm", "Calendar: Mac → Palm") }
    static var calendarSyncTitleTwoWay: String { s("Kalender: Mac ↔ Palm", "Calendar: Mac ↔ Palm") }
    static var calendarSyncToggle: String { s("Kalender abgleichen", "Sync Calendar") }
    static var calendarSyncChoose: String { s("Kalender wählen", "Choose calendars") }
    static var calendarSyncWarning: String { s(
        "Der Kalender des Palms wird dabei ersetzt: Einträge, die auf dem Palm geändert wurden, gehen verloren.",
        "The Palm's calendar is replaced: entries edited on the Palm are lost."
    ) }
    static var calendarSyncAllow: String { s("Zugriff auf Kalender erlauben …", "Allow access to Calendar …") }
    static var calendarSyncDenied: String { s(
        "Kein Zugriff auf Kalender: in den Systemeinstellungen unter Datenschutz & Sicherheit › Kalender erlauben",
        "No access to Calendar: allow it in System Settings under Privacy & Security › Calendars"
    ) }
    static var calendarSubscribed: String { s("abonniert", "subscribed") }
    static var calendarGone: String { s("nicht mehr vorhanden", "no longer exists") }
    static var calendarSyncCategory: String { s("Kategorie", "Category") }
    static var calendarSyncCategoryHelp: String { s(
        "Kategorie auf dem Palm (bis 15 Zeichen); leer: der Name des Kalenders. Mehrere Kalender können eine teilen.",
        "Category on the Palm (up to 15 characters); empty: the calendar's name. Several calendars can share one."
    ) }
    static var calendarSyncWindowLabel: String { s("Zeitraum:", "Window:") }
    static func calendarSyncDays(_ days: Int, back: Bool) -> String {
        back ? s("\(days) Tage zurück", "\(days) days back") : s("\(days) Tage voraus", "\(days) days ahead")
    }
    static var calendarSyncNoCalendars: String { s("Noch kein Kalender gewählt", "No calendar chosen yet") }
    static func calendarSyncPreview(_ records: Int, _ series: Int, _ expanded: Int) -> String { s(
        "\(records) Einträge beim nächsten HotSync (\(series) Serien, \(expanded) aufgelöst)",
        "\(records) records at the next HotSync (\(series) series, \(expanded) expanded)"
    ) }
    static func logCalendarQueued(_ records: Int, _ series: Int, _ bytes: Int) -> String { s(
        "Kalender gebaut: \(records) Einträge (\(series) Serien), CalendarDB-PDat.pdb (\(bytes) Bytes) in der Warteschlange",
        "Calendar built: \(records) records (\(series) series), CalendarDB-PDat.pdb (\(bytes) bytes) queued"
    ) }
    static func logCalendarWarning(_ text: String) -> String { s("Kalender: \(text)", "Calendar: \(text)") }
    static var logCalendarNeedsBackup: String { s(
        "Kalender noch nicht auf den Palm gespielt: erst muss eine Sicherung dieses Palms da sein (dieser HotSync legt sie an)",
        "Calendar not put on the Palm yet: a backup of this Palm has to exist first (this HotSync makes it)"
    ) }
    static var logCalendarNoAccess: String { s(
        "Kalender nicht gebaut: kein Zugriff auf Kalender", "Calendar not built: no access to Calendar"
    ) }
    static func logCalendarFailed(_ reason: String) -> String { s(
        "Kalender nicht gebaut: \(reason)", "Calendar not built: \(reason)"
    ) }
    static func logCalendarChecking(_ name: String) -> String { s(
        "Prüfe \(name) auf dem Palm …", "Checking \(name) on the Palm …"
    ) }
    static func logCalendarChecked(_ name: String, _ records: Int, _ identical: Int, _ different: Int, _ deleted: Int, _ categories: [String]) -> String { s(
        "\(name) auf dem Palm: \(records) Datensätze, \(identical) identisch, \(different) abweichend, \(deleted) gelöscht; Kategorien: \(categories.joined(separator: ", "))",
        "\(name) on the Palm: \(records) records, \(identical) decode, \(different) differ, \(deleted) deleted; categories: \(categories.joined(separator: ", "))"
    ) }
    static var dryRunTitle: String { s("Probelauf", "Dry run") }
    static var dryRunToggle: String { s("Probelauf: nichts schreiben, nur ins Log", "Dry run: write nothing, only log") }
    static var dryRunHint: String { s(
        "Gilt für alle Abgleiche dieses Palms: Kalender, Kontakte, Aufgaben, Uhr und Zeitzonen schreiben auf keiner Seite etwas und tragen ins Log ein, was sie tun würden. Die Sicherung läuft; in die Warteschlange gelegte Dateien werden trotzdem installiert.",
        "Applies to every sync of this Palm: Calendar, Contacts, Tasks, clock and time zones write nothing on either side and log what they would do. The backup still runs; files dropped into the queue are still installed."
    ) }
    static var logWakeRestart: String { s(
        "Aufgewacht: Listener werden neu gestartet", "Woke up: restarting the listeners"
    ) }
    static var massDeleteToggle: String { s(
        "Viele Änderungen beim nächsten Abgleich zulassen", "Allow many changes at the next sync"
    ) }
    static var massDeleteHint: String { s(
        "Ein Abgleich, der zehn oder mehr vorhandene Einträge (oder ein Fünftel) auf einer Seite löschen oder ändern würde, wird sonst verweigert – meist steckt eine leere Quelle, ein zurückgesetzter Palm oder eine falsche Zuordnung dahinter, keine Absicht. Neue Einträge zählen nicht. Gilt für einen HotSync und schaltet sich danach aus.",
        "A sync that would delete or change ten or more existing items (or a fifth) on one side is otherwise refused – usually that is an empty source, a reset Palm or a wrong mapping, not intent. New items do not count. Applies to one HotSync and switches itself off afterwards."
    ) }
    static var logMassAllowReset: String { s(
        "„Viele Änderungen zulassen“ ist wieder aus", "“Allow many changes” is off again"
    ) }
    static func logTwoWayTruncated(_ what: String, _ got: Int, _ expected: Int) -> String { s(
        "\(what): nur \(got) von \(expected) Datensätzen gelesen – Abgleich ausgelassen, nichts geändert",
        "\(what): only \(got) of \(expected) records read – sync skipped, nothing changed"
    ) }
    static func logTwoWayDeletesUntrusted(_ what: String) -> String { s(
        "\(what): zuletzt hat ein anderer PC abgeglichen (oder der Palm wurde zurückgesetzt): auf dem Mac wird nichts gelöscht, was auf dem Palm fehlt, kommt dorthin zurück",
        "\(what): another PC synced last (or the Palm was reset): nothing is deleted on the Mac, what the Palm lacks goes back to it"
    ) }
    static func massChangeText(_ m: SyncMassChange) -> String { s(
        "Mac: \(m.macDeletes) löschen, \(m.macUpdates) ändern; Palm: \(m.palmDeletes) löschen, \(m.palmUpdates) ändern",
        "Mac: \(m.macDeletes) deleted, \(m.macUpdates) changed; Palm: \(m.palmDeletes) deleted, \(m.palmUpdates) changed"
    ) }
    static func logTwoWayMassRefused(_ what: String, _ m: SyncMassChange, mirror: Int) -> String { s(
        "\(what): verweigert – \(massChangeText(m)) (Spiegel: \(mirror)). Prüfen, dann „Viele Änderungen zulassen“ einschalten, wenn das stimmt",
        "\(what): refused – \(massChangeText(m)) (mirror: \(mirror)). Check, then turn on “Allow many changes” if that is right"
    ) }
    static func logTwoWayMassAllowed(_ what: String, _ m: SyncMassChange) -> String { s(
        "\(what): \(massChangeText(m)) – wie erlaubt; der Schalter ist wieder aus",
        "\(what): \(massChangeText(m)) – as allowed; the switch is off again"
    ) }
    static var logTwoWayRestoreSkipped: String { s(
        "Abgleich in beide Richtungen in dieser Sitzung ausgelassen: nach dem Zurückspielen beim nächsten HotSync",
        "Two-way sync skipped in this session: after a restore, at the next HotSync"
    ) }
    static func logPalmOSTooOld(_ version: String) -> String { s(
        "Palm OS \(version): Kalender, Kontakte, Aufgaben und Zeitzonen brauchen Palm OS 5.2 oder neuer – ausgelassen",
        "Palm OS \(version): Calendar, Contacts, Tasks and time zones need Palm OS 5.2 or later – skipped"
    ) }
    static func palmOSTooOld(_ version: String) -> String { s(
        "Dieser Palm hat Palm OS \(version). Der Abgleich von Kalender, Kontakten und Aufgaben und die Zeitzonen brauchen die Garnet-Programme ab Palm OS 5.2 (Tungsten T3 und neuer); Installieren, Sichern und Zurückspielen gehen wie immer.",
        "This Palm runs Palm OS \(version). Syncing Calendar, Contacts and Tasks and the time zones need the Garnet applications of Palm OS 5.2 and later (Tungsten T3 onwards); install, backup and restore work as always."
    ) }
    static func logTwoWayMirrorBroken(_ what: String, _ file: String, _ reason: String) -> String { s(
        "\(what): der Spiegel \(file) lässt sich nicht lesen (\(reason)) – Abgleich ausgelassen; Datei prüfen oder beiseitelegen, dann paart der nächste HotSync nach Inhalt",
        "\(what): the mirror \(file) cannot be read (\(reason)) – sync skipped; check or set the file aside, then the next HotSync pairs by content"
    ) }
    static func logTwoWayAsking(_ what: String, _ count: Int) -> String { s(
        "\(what): \(count) Konflikte – der Palm wartet auf die Entscheidung", "\(what): \(count) conflicts – the Palm waits for the decision"
    ) }
    static func logTwoWayAnswered(_ what: String, mac: Int, palm: Int, both: Int) -> String { s(
        "\(what): entschieden – \(mac)× Mac, \(palm)× Palm, \(both)× beide", "\(what): decided – \(mac)× Mac, \(palm)× Palm, \(both)× both"
    ) }
    static func logTwoWaySkippedByUser(_ what: String) -> String { s(
        "\(what): Abgleich ausgelassen, wie im Dialog gewählt", "\(what): sync skipped, as chosen in the dialog"
    ) }
    static var logTwoWayAskAbandoned: String { s(
        "Der Palm ist weg, bevor die Konflikte entschieden waren: nichts geschrieben", "The Palm left before the conflicts were decided: nothing written"
    ) }
    static func conflictAskTitle(_ what: String, _ palm: String) -> String { s("Konflikte: \(what) · \(palm)", "Conflicts: \(what) · \(palm)") }
    static var conflictAskHint: String { s(
        "Beide Seiten haben dasselbe Feld verschieden geändert. Der Palm wartet, bis entschieden ist; „Auslassen“ lässt diesen Abgleich für heute aus, auf keiner Seite wird etwas geschrieben.",
        "Both sides changed the same field differently. The Palm waits until this is decided; “Skip” leaves this sync out for today, nothing is written on either side."
    ) }
    static var conflictAskMac: String { s("Mac", "Mac") }
    static var conflictAskPalm: String { s("Palm", "Palm") }
    static var conflictAskBoth: String { s("Beide", "Both") }
    static var conflictAskAllMac: String { s("Überall Mac", "Mac for all") }
    static var conflictAskAllPalm: String { s("Überall Palm", "Palm for all") }
    static var conflictAskSkip: String { s("Auslassen", "Skip") }
    static var conflictAskApply: String { s("Anwenden", "Apply") }
    static var logDryRun: String { s("Probelauf: die Abgleiche schreiben nichts", "Dry run: the syncs write nothing") }
    static var logDryRunClock: String { s("Probelauf: die Uhr des Palms würde gestellt werden", "Dry run: the Palm's clock would be set") }
    static func logDryRunWouldInstall(_ name: String, _ records: Int, _ bytes: Int) -> String { s(
        "Probelauf: \(name) würde installiert werden (\(records) Einträge, \(bytes) Bytes), liegt unter Sync/DryRun",
        "Dry run: \(name) would be installed (\(records) records, \(bytes) bytes), kept under Sync/DryRun"
    ) }
    static var twoWayToggle: String { s("In beide Richtungen", "Two-way") }
    static var twoWayHintContacts: String { s(
        "Der HotSync liest die Kontakte des Palms, führt sie Feld für Feld mit dem Mac zusammen und schreibt beide Seiten: Mac-Änderungen über die Kontakte-Schnittstelle von macOS in Kontakte.app (und damit in iCloud), der Palm bekommt die zusammengeführten Kontakte als Ganzes. Notizen und was über die Felder des Palms hinausgeht, bleiben auf dem Mac.",
        "The HotSync reads the Palm's contacts, merges them field by field with the Mac and writes both sides: Mac changes through the Contacts framework into Contacts.app (and on to iCloud), the Palm gets the merged contacts whole. Notes and whatever exceeds the Palm's fields stay on the Mac."
    ) }
    static var twoWayHintTasks: String { s(
        "Der HotSync liest die Aufgaben des Palms, führt sie Feld für Feld mit dem Mac zusammen und schreibt beide Seiten: Mac-Änderungen über EventKit in Erinnerungen.app (und damit in iCloud), der Palm bekommt die zusammengeführten Aufgaben als Ganzes.",
        "The HotSync reads the Palm's tasks, merges them field by field with the Mac and writes both sides: Mac changes through EventKit into Reminders.app (and on to iCloud), the Palm gets the merged tasks whole."
    ) }
    static var twoWayHint: String { s(
        "Der HotSync liest den Kalender des Palms, führt ihn Feld für Feld mit dem Mac zusammen und schreibt beide Seiten: Mac-Änderungen über EventKit in Kalender.app (und damit in iCloud/Google), der Palm bekommt den zusammengeführten Kalender als Ganzes. Beim ersten Mal lohnt sich ein Probelauf.",
        "The HotSync reads the Palm's calendar, merges it field by field with the Mac and writes both sides: Mac changes through EventKit into Calendar.app (and on to iCloud/Google), the Palm gets the merged calendar whole. A dry run first is worth it."
    ) }
    static var twoWayCalendar: String { s("Kalender", "Calendar") }
    static var twoWayContacts: String { s("Kontakte", "Contacts") }
    static var twoWayTasks: String { s("Aufgaben", "Tasks") }
    static func logTwoWayPending(_ what: String) -> String { s(
        "\(what): Abgleich in beide Richtungen nach der Sicherung",
        "\(what): two-way sync after the backup; nothing is installed whole"
    ) }
    static func logTwoWayReading(_ what: String) -> String { s("\(what): lese vom Palm …", "\(what): reading from the Palm …") }
    static func logTwoWayMode(_ what: String, fast: Bool, lastSyncPC: UInt32, mirrorEntries: Int) -> String { s(
        fast ? "\(what): zuletzt hat dieser Mac abgeglichen (Spiegel mit \(mirrorEntries) Einträgen): Löschungen auf dem Palm zählen" : "\(what): zuletzt ein anderer PC oder keiner (Spiegel: \(mirrorEntries) Einträge, letzter PC \(lastSyncPC)): Datensätze werden nach Inhalt gepaart, auf dem Mac wird nichts gelöscht",
        fast ? "\(what): this Mac synced last (mirror with \(mirrorEntries) entries): the Palm's deletions count" : "\(what): another PC or none synced last (mirror: \(mirrorEntries) entries, last PC \(lastSyncPC)): records are paired by content, nothing is deleted on the Mac"
    ) }
    static func logTwoWaySummary(_ what: String, toPalm: Int, palmDeletes: Int, toMac: Int, macDeletes: Int, conflicts: Int, policy: ConflictPolicy) -> String { s(
        "\(what): \(toPalm) auf den Palm, \(palmDeletes) dort löschen; \(toMac) auf den Mac, \(macDeletes) dort löschen; \(conflicts) Konflikte (\(conflictPolicyName(policy)))",
        "\(what): \(toPalm) to the Palm, \(palmDeletes) deleted there; \(toMac) to the Mac, \(macDeletes) deleted there; \(conflicts) conflicts (\(conflictPolicyName(policy)))"
    ) }
    static var conflictPolicyLabel: String { s("Bei Konflikten:", "On conflicts:") }
    static func conflictPolicyName(_ p: ConflictPolicy) -> String {
        switch p {
        case .macWins: return s("Mac gewinnt", "Mac wins")
        case .palmWins: return s("Palm gewinnt", "Palm wins")
        case .keepBoth: return s("beide behalten", "keep both")
        case .ask: return s("fragen", "ask")
        }
    }
    static var conflictPolicyHelp: String { s(
        "Wenn beide Seiten dasselbe Feld desselben Eintrags verschieden geändert haben. „Beide behalten“ legt die Palm-Fassung als zweiten Eintrag auf beiden Seiten an, wie es Palm Desktop tat.",
        "When both sides changed the same field of the same event differently. “Keep both” makes the Palm's version a second event on both sides, as the Palm Desktop did."
    ) }
    static func logTwoWayToPalm(_ title: String, new: Bool) -> String { s(
        new ? "→ Palm (neu): \(title)" : "→ Palm: \(title)", new ? "→ Palm (new): \(title)" : "→ Palm: \(title)"
    ) }
    static func logTwoWayToMac(_ title: String, new: Bool) -> String { s(
        new ? "→ Mac (neu): \(title)" : "→ Mac: \(title)", new ? "→ Mac (new): \(title)" : "→ Mac: \(title)"
    ) }
    static func logTwoWayConflict(_ title: String, _ field: String, _ palm: String, _ mac: String, policy: ConflictPolicy) -> String { s(
        "Konflikt \(title) · \(field): Palm „\(palm)“, Mac „\(mac)“ – \(conflictPolicyName(policy))",
        "Conflict \(title) · \(field): Palm “\(palm)”, Mac “\(mac)” – \(conflictPolicyName(policy))"
    ) }
    static func logTwoWayMissingCategories(_ names: [String]) -> String { s(
        "Kategorien, die der Palm noch nicht hat: \(names.joined(separator: ", "))",
        "Categories the Palm does not have yet: \(names.joined(separator: ", "))"
    ) }
    static var logTwoWayDryRunDone: String { s("Probelauf beendet, nichts geschrieben", "Dry run done, nothing written") }
    static func logTwoWayMacApplied(_ created: Int, _ updated: Int, _ deleted: Int) -> String { s(
        "Mac: \(created) neu, \(updated) geändert, \(deleted) gelöscht", "Mac: \(created) created, \(updated) updated, \(deleted) deleted"
    ) }
    static func logTwoWayMacFailure(_ text: String) -> String { s("Auf dem Mac nicht geschrieben: \(text)", "Mac, not written: \(text)") }
    static func logTwoWayPalmInstalling(_ what: String, _ records: Int) -> String { s(
        "Palm: \(what) zusammengeführt, \(records) Einträge werden installiert …", "Palm: installing the merged \(what) (\(records) records) …"
    ) }
    static func logTwoWayPalmUnchanged(_ what: String) -> String { s(
        "Palm: \(what) unverändert, nichts wird installiert", "Palm: \(what) unchanged, nothing is installed"
    ) }
    static func logTwoWayMirrorSaved(_ entries: Int) -> String { s(
        "Spiegel gespeichert: \(entries) Einträge", "Mirror saved: \(entries) entries"
    ) }
    static var logTwoWayDone: String { s("Abgleich in beide Richtungen fertig; dieser Mac ist als letzter PC eingetragen", "Two-way sync done; this Mac is recorded as the last PC") }
    static func logTwoWayFailed(_ reason: String) -> String { s("Abgleich abgebrochen: \(reason)", "Sync stopped: \(reason)") }
    static var taskSyncTitle: String { s("Aufgaben: Mac → Palm", "Tasks: Mac → Palm") }
    static var taskSyncTitleTwoWay: String { s("Aufgaben: Mac ↔ Palm", "Tasks: Mac ↔ Palm") }
    static var taskSyncToggle: String { s("Aufgaben abgleichen", "Sync Tasks") }
    static var taskSyncChoose: String { s("Listen wählen", "Choose lists") }
    static var taskSyncWarning: String { s(
        "Die Aufgaben des Palms werden dabei ersetzt: Einträge, die auf dem Palm geändert wurden, gehen verloren.",
        "The Palm's tasks are replaced: entries edited on the Palm are lost."
    ) }
    static var taskSyncAllow: String { s("Zugriff auf Erinnerungen erlauben …", "Allow access to Reminders …") }
    static var taskSyncDenied: String { s(
        "Kein Zugriff auf Erinnerungen: in den Systemeinstellungen unter Datenschutz & Sicherheit › Erinnerungen erlauben",
        "No access to Reminders: allow it in System Settings under Privacy & Security › Reminders"
    ) }
    static var taskSyncHint: String { s(
        "Jede Liste wird zu einer Kategorie auf dem Palm (bis 15). Erledigte Aufgaben bleiben so viele Tage auf dem Palm:",
        "Each list becomes a category on the Palm (up to 15). Completed tasks stay on the Palm for this many days:"
    ) }
    static func taskSyncDays(_ days: Int) -> String { s("\(days) Tage", "\(days) days") }
    static var taskSyncNoLists: String { s("Noch keine Liste gewählt", "No list chosen yet") }
    static func taskSyncPreview(_ records: Int, _ categories: Int, _ skipped: Int) -> String { s(
        "\(records) Aufgaben beim nächsten HotSync (\(categories) Kategorien, \(skipped) alte erledigte weggelassen)",
        "\(records) tasks at the next HotSync (\(categories) categories, \(skipped) old completed ones left out)"
    ) }
    static func logTasksQueued(_ records: Int, _ skipped: Int, _ bytes: Int) -> String { s(
        "Aufgaben gebaut: \(records) Einträge (\(skipped) alte erledigte weggelassen), TasksDB-PTod.pdb (\(bytes) Bytes) in der Warteschlange",
        "Tasks built: \(records) records (\(skipped) old completed ones left out), TasksDB-PTod.pdb (\(bytes) bytes) queued"
    ) }
    static func logTasksWarning(_ text: String) -> String { s("Aufgaben: \(text)", "Tasks: \(text)") }
    static var logTasksNoAccess: String { s(
        "Aufgaben nicht gebaut: kein Zugriff auf Erinnerungen", "Tasks not built: no access to Reminders"
    ) }
    static func logTasksFailed(_ reason: String) -> String { s("Aufgaben nicht gebaut: \(reason)", "Tasks not built: \(reason)") }
    static var logTasksNeedBackup: String { s(
        "Aufgaben noch nicht auf den Palm gespielt: erst muss eine Sicherung dieses Palms da sein (dieser HotSync legt sie an)",
        "Tasks not put on the Palm yet: a backup of this Palm has to exist first (this HotSync makes it)"
    ) }
    static var timeSyncTitle: String { s("Uhr, Zeitzonen und Netzwerk", "Clock, time zones and network") }
    static var netSyncToggle: String { s(
        "Diesen Mac als primären PC für den Netzwerk-HotSync eintragen", "Set this Mac as the Palm's primary PC for network HotSync"
    ) }
    static func netSyncHint(_ ip: String?, _ name: String) -> String { s(
        "Bei jedem Kabel-HotSync bekommt der Palm Adresse und Namen dieses Macs (\(ip ?? "–"), \(name)) in seine Netzwerk-HotSync-Einstellungen, wie beim HotSync-Manager. Danach steht unter HotSync › Menü › Primäres PC-Setup schon dieser Mac; für einen HotSync über WLAN braucht ein Tab den Anschluss „Netzwerk (WLAN)“.",
        "At each cable HotSync the Palm gets this Mac's address and name (\(ip ?? "–"), \(name)) in its network HotSync settings, as HotSync Manager did. HotSync › menu › Primary PC Setup then already shows this Mac; a HotSync over Wi-Fi needs a tab on the “Network (Wi-Fi)” port."
    ) }
    static func logNetSyncSet(_ address: String, _ name: String) -> String { s(
        "Primärer PC im Palm eingetragen: \(name) (\(address))", "Primary PC written to the Palm: \(name) (\(address))"
    ) }
    static var logNetSyncNoAddress: String { s(
        "Kein primärer PC eingetragen: dieser Mac hat keine Netzwerkadresse", "Primary PC not written: this Mac has no network address"
    ) }
    static func logDryRunNetSync(_ address: String) -> String { s(
        "Probelauf: dieser Mac (\(address)) würde als primärer PC eingetragen werden", "Dry run: this Mac (\(address)) would be written as the primary PC"
    ) }
    static var clockSyncToggle: String { s("Uhr des Palms vom Mac stellen", "Set the Palm's clock from the Mac") }
    static var clockSyncHint: String { s(
        "Bei jedem HotSync, wie beim HotSync-Manager.", "At each HotSync, as the HotSync Manager did."
    ) }
    static var zoneSyncToggle: String { s("Zeitzonen des Palms mit den Zeitzonendaten des Macs aktualisieren", "Update the Palm's time zones from the Mac's tzdata") }
    static var zoneSyncHint: String { s(
        "Die Orte des Palms (Einstellungen › Datum & Uhrzeit) bekommen bei jedem HotSync die Zeitzonen-Regeln aus den Zeitzonendaten des Macs – ein Palm OS 5 kennt weder die Regeln von 2007 noch eine Provinz, die die Uhr nicht mehr umstellt. Nach einer Änderung: Soft-Reset, Heimatort in Prefs neu wählen, noch ein HotSync.",
        "The Palm's locations (Prefs › Date & Time) get the time zone rules from the Mac's tzdata at each HotSync – a Palm OS 5 knows neither the 2007 rules nor a province that stopped changing clocks. After a change: soft reset, pick the home location in Prefs again, one more HotSync."
    ) }
    static func logDateFix(_ startYear: Int) -> String { s(
        "DateFix auf dem Palm: Startjahr \(startYear), Daten und Uhr werden um \(startYear - 1904) Jahre umgerechnet",
        "DateFix on the Palm: start year \(startYear), dates and clock are converted by \(startYear - 1904) years"
    ) }
    static func logDateFixChanged(_ what: String, from old: Int, to new: Int) -> String { s(
        "\(what): DateFix auf dem Palm hat sich geändert (Startjahr \(old) → \(new)): seine Daten bedeuten jetzt andere Jahre. Sie werden mit dem alten Startjahr gelesen und alle im neuen zurückgeschrieben; das zählt als viele Änderungen",
        "\(what): DateFix on the Palm changed (start year \(old) → \(new)): its dates now mean other years. They are read with the old start year and all written back in the new one; that counts as many changes"
    ) }
    static func logTimeSetDateFix(_ real: Date, storedYear: Int) -> String { s(
        "Uhr des Palms gestellt: \(real.formatted(date: .abbreviated, time: .shortened)) (DateFix: gespeichert als \(storedYear))",
        "Palm clock set: \(real.formatted(date: .abbreviated, time: .shortened)) (DateFix: stored as \(storedYear))"
    ) }
    static func logTimeSet(_ date: Date) -> String { s(
        "Uhr des Palms gestellt: \(date.formatted(date: .abbreviated, time: .shortened))",
        "Palm clock set: \(date.formatted(date: .abbreviated, time: .shortened))"
    ) }
    static func logLocationsChecking(_ name: String) -> String { s(
        "Prüfe die Zeitzonen in \(name) …", "Checking the time zones in \(name) …"
    ) }
    static func logLocationFixed(_ change: String) -> String { s("Zeitzone: \(change)", "Time zone: \(change)") }
    static func logLocationsDone(_ name: String, _ changed: Int, _ total: Int, _ unknown: Int) -> String { s(
        "\(name): \(changed) von \(total) Orten abweichend, \(unknown) ohne bekannte Zone",
        "\(name): \(changed) of \(total) locations differ, \(unknown) with no known zone"
    ) }
    static var logLocationsReordered: String { s(
        "Orte in die Reihenfolge der Auswahlliste gebracht (Zone, dann Stadt)",
        "Locations put in the picker's order (zone, then city)"
    ) }
    static func logLocationsInstalled(_ name: String) -> String { s(
        "\(name) korrigiert auf den Palm gespielt", "\(name) installed with the corrections"
    ) }
    static var logLocationsHint: String { s(
        "Auf dem Palm: erst ein Soft-Reset (die Ortsliste ist zwischengespeichert und zeigt sonst auf falsche Einträge), dann Prefs › Datum & Uhrzeit, Heimatort neu wählen, dann noch ein HotSync für die Uhr",
        "On the Palm: soft reset first (its location list is cached and otherwise points at the wrong entries), then Prefs › Date & Time, pick the home location again, then one more HotSync for the clock"
    ) }
    static func logLocationsFailed(_ name: String, _ stage: String, _ message: String) -> String { s(
        "Zeitzonen in \(name) nicht geändert (\(stage): \(message))", "Time zones in \(name) not changed (\(stage): \(message))"
    ) }
    static var contactSyncTitle: String { s("Kontakte: Mac → Palm", "Contacts: Mac → Palm") }
    static var contactSyncTitleTwoWay: String { s("Kontakte: Mac ↔ Palm", "Contacts: Mac ↔ Palm") }
    static var contactSyncToggle: String { s("Kontakte abgleichen", "Sync Contacts") }
    static var contactSyncChoose: String { s("Konten wählen", "Choose accounts") }
    static var contactSyncWarning: String { s(
        "Die Kontakte des Palms werden dabei ersetzt: Einträge, die auf dem Palm geändert wurden, gehen verloren.",
        "The Palm's contacts are replaced: entries edited on the Palm are lost."
    ) }
    static var contactSyncAllow: String { s("Zugriff auf Kontakte erlauben …", "Allow access to Contacts …") }
    static var contactSyncDenied: String { s(
        "Kein Zugriff auf Kontakte: in den Systemeinstellungen unter Datenschutz & Sicherheit › Kontakte erlauben",
        "No access to Contacts: allow it in System Settings under Privacy & Security › Contacts"
    ) }
    static var contactSyncGroupsHint: String { s(
        "Gruppen werden zu Kategorien auf dem Palm (bis 15); Notizen bleiben auf dem Mac, macOS gibt sie nicht frei.",
        "Groups become categories on the Palm (up to 15); notes stay on the Mac, macOS does not hand them out."
    ) }
    static var contactSyncNoContainers: String { s("Noch kein Konto gewählt", "No account chosen yet") }
    static func contactSyncPreview(_ records: Int, _ categories: Int, _ duplicates: Int) -> String { s(
        "\(records) Kontakte beim nächsten HotSync (\(categories) Kategorien, \(duplicates) doppelte weggelassen)",
        "\(records) contacts at the next HotSync (\(categories) categories, \(duplicates) duplicates dropped)"
    ) }
    static func logContactsQueued(_ records: Int, _ categories: Int, _ bytes: Int) -> String { s(
        "Kontakte gebaut: \(records) Einträge (\(categories) Kategorien), ContactsDB-PAdd.pdb (\(bytes) Bytes) in der Warteschlange",
        "Contacts built: \(records) records (\(categories) categories), ContactsDB-PAdd.pdb (\(bytes) bytes) queued"
    ) }
    static func logContactsWarning(_ text: String) -> String { s("Kontakte: \(text)", "Contacts: \(text)") }
    static var logContactsNoAccess: String { s(
        "Kontakte nicht gebaut: kein Zugriff auf Kontakte", "Contacts not built: no access to Contacts"
    ) }
    static func logContactsFailed(_ reason: String) -> String { s(
        "Kontakte nicht gebaut: \(reason)", "Contacts not built: \(reason)"
    ) }
    static var logContactsNeedBackup: String { s(
        "Kontakte noch nicht auf den Palm gespielt: erst muss eine Sicherung dieses Palms da sein (dieser HotSync legt sie an)",
        "Contacts not put on the Palm yet: a backup of this Palm has to exist first (this HotSync makes it)"
    ) }
    static func logCalendarRecordDiffers(_ id: UInt32, _ bytes: Int, _ hex: String) -> String { s(
        "Datensatz \(id) (\(bytes) Bytes) weicht nach dem Neukodieren ab: \(hex) …",
        "Record \(id) (\(bytes) bytes) does not come back the same: \(hex) …"
    ) }
    static func logCalendarCheckFailed(_ name: String, _ stage: String, _ message: String) -> String { s(
        "Prüfung von \(name) abgebrochen (\(stage): \(message))", "Check of \(name) stopped (\(stage): \(message))"
    ) }
    static func phaseReadingCalendar(_ name: String, _ database: String, _ done: Int) -> String { s(
        "Prüfe \(database) von \(name) … \(done) Datensätze", "Checking \(name)'s \(database) … \(done) records"
    ) }

    static func logBackupFinished(_ saved: Int, _ unchanged: Int, _ failed: Int) -> String { s(
        "Sicherung fertig: \(saved) neu oder geändert, \(unchanged) unverändert, \(failed) nicht lesbar",
        "Backup done: \(saved) new or changed, \(unchanged) unchanged, \(failed) unreadable"
    ) }
    static var logPalmLost: String { s(
        "Der Palm antwortet nicht mehr: Sitzung beendet, der Rest entfällt", "The Palm no longer answers: session ended, the rest is skipped"
    ) }
    static var logBackupIncomplete: String { s(
        "Sicherung abgebrochen – die bis dahin geholten Datenbanken sind gesichert, die übrigen haben ihren alten Stand",
        "Backup cut short – the databases fetched so far are saved, the others keep their previous state"
    ) }
    static func logRestoreStarting(_ count: Int) -> String { s(
        "Sicherung wird zurückgespielt: \(count) Datenbanken …", "Restoring the backup: \(count) databases …"
    ) }
    static func logRestoreFailed(_ name: String, _ reason: String) -> String { s(
        "\(name) NICHT zurückgespielt (\(reason))", "\(name) NOT restored (\(reason))"
    ) }
    static func logRestoreFinished(_ installed: Int, _ failed: Int) -> String { s(
        "Zurückgespielt: \(installed) Datenbanken, \(failed) nicht", "Restored: \(installed) databases, \(failed) not"
    ) }

    static func logROMRequested(_ path: String) -> String { s("ROM wird ausgelesen nach \(path) …", "Reading the ROM to \(path) …") }
    static func logROMStarting(_ version: String, _ total: Int, _ file: String) -> String { s(
        "ROM von Palm OS \(version): \(megabytes(total)) → \(file)", "ROM of Palm OS \(version): \(megabytes(total)) → \(file)"
    ) }
    static func logROMFinished(_ file: String, _ bytes: Int) -> String { s(
        "ROM ausgelesen: \(file) (\(megabytes(bytes)))", "ROM read: \(file) (\(megabytes(bytes)))"
    ) }
    static func logROMUnsupported(_ version: String) -> String { s(
        "ROM nicht ausgelesen: Palm OS \(version) – über HotSync geht das nur bis Palm OS 4",
        "ROM not read: Palm OS \(version) – over HotSync this only works up to Palm OS 4"
    ) }
    static func logROMFailed(_ message: String) -> String { s(
        "ROM-Auslesen abgebrochen: \(message) – unvollständig nicht gespeichert",
        "Reading the ROM stopped: \(message) – nothing incomplete saved"
    ) }
    static var romNotReached: String { s(
        "die Sitzung endete vorher", "the session ended before"
    ) }
    static func megabytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
    static func phaseDumpingROM(_ name: String, _ done: Int, _ total: Int) -> String {
        total == 0
            ? s("\(name): ROM wird vorbereitet …", "\(name): preparing the ROM …")
            : s("\(name): ROM wird ausgelesen, \(megabytes(done)) von \(megabytes(total))",
                "\(name): reading the ROM, \(megabytes(done)) of \(megabytes(total))")
    }
    static func resultROM(_ dump: TabStatus.ROMDump) -> String {
        switch dump {
        case .saved(let file, let bytes):
            return s("ROM ausgelesen: \(file) (\(megabytes(bytes)))", "ROM read: \(file) (\(megabytes(bytes)))")
        case .unsupported(let version):
            return s("ROM nicht ausgelesen: Palm OS \(version) – geht über HotSync nur bis Palm OS 4",
                     "ROM not read: Palm OS \(version) – over HotSync only up to Palm OS 4")
        case .failed(let message):
            return s("ROM nicht ausgelesen: \(message)", "ROM not read: \(message)")
        }
    }

    // MARK: - Sicherung (Menü)

    static var romDumpNext: String { s("ROM beim nächsten HotSync auslesen", "Read the ROM at the next HotSync") }
    static var romDumpCancel: String { s("ROM-Auslesen abbrechen", "Cancel reading the ROM") }
    static func romDumpUnsupported(_ version: String) -> String { s(
        "ROM auslesen geht nur bis Palm OS 4 (dieses Gerät: \(version))",
        "Reading the ROM only works up to Palm OS 4 (this device: \(version))"
    ) }
    static var romOpenFolder: String { s("ROM im Finder zeigen", "Show the ROM in the Finder") }
    static var romDumpPending: String { s(
        "Beim nächsten HotSync wird das ROM ausgelesen", "The ROM is read at the next HotSync"
    ) }

    static var backupMenu: String { s("Sicherung", "Backup") }
    static var backupMenuHelp: String { s("Sicherung dieses Palms: zurückspielen, im Finder zeigen", "This Palm's backup: restore, show in the Finder") }
    static var tabSyncModeLabel: String { s("HotSync:", "HotSync:") }
    static var backupRestoreNext: String { s("Beim nächsten HotSync zurückspielen …", "Restore at the next HotSync …") }
    static var backupRestoreCancel: String { s("Zurückspielen abbrechen", "Cancel the restore") }
    static var backupOpenFolder: String { s("Sicherung im Finder zeigen", "Show the backup in the Finder") }
    static func backupSummary(_ count: Int, _ date: String?) -> String {
        guard count > 0 else { return s("Noch keine Sicherung", "No backup yet") }
        return date.map { s("\(count) Datenbanken, Stand \($0)", "\(count) databases, as of \($0)") }
            ?? s("\(count) Datenbanken", "\(count) databases")
    }
    static var backupRestorePending: String { s(
        "Beim nächsten HotSync wird die Sicherung zurückgespielt",
        "The backup goes back onto the Palm at the next HotSync"
    ) }
    static var restoreConfirmTitle: String { s("Sicherung zurückspielen?", "Restore the backup?") }
    static func restoreConfirmMessage(_ name: String, _ summary: String) -> String { s(
        "Beim nächsten HotSync von „\(name)“ gehen alle Datenbanken der Sicherung (\(summary)) auf den Palm. Gleichnamige Datenbanken auf dem Palm werden dabei durch den Stand der Sicherung ersetzt.",
        "At the next HotSync of “\(name)”, all databases of the backup (\(summary)) go onto the Palm. Databases of the same name on the Palm are replaced by the backup's version."
    ) }
    static var restoreConfirm: String { s("Zurückspielen", "Restore") }
    static func newPalmRestore(_ summary: String) -> String { s(
        "Sicherung zurückspielen (\(summary))", "Restore the backup (\(summary))"
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
    static func sessionCrashed(_ signal: Int) -> String { s(
        "hotsync-session ist abgestürzt (Signal \(signal))", "hotsync-session crashed (signal \(signal))"
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
    static func logTrashFailed(_ path: String, _ err: String) -> String { s(
        "\(path) konnte nicht in den Papierkorb: \(err)", "Could not move \(path) to the Trash: \(err)"
    ) }
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
    static func logQueueMoved(_ name: String, _ dir: String) -> String { s(
        "Verschoben: \(name) → Warteschlange \(dir)", "Moved: \(name) → queue \(dir)"
    ) }
    static func logQueueMoveFailed(_ name: String, _ err: String) -> String { s(
        "\(name) konnte nicht verschoben werden: \(err)", "Could not move \(name): \(err)"
    ) }
    static func logQueueMoveBusy(_ name: String) -> String { s(
        "\(name) wird gerade übertragen und bleibt in der Warteschlange",
        "\(name) is being transferred and stays in the queue"
    ) }
    static func logCopyFailed(_ name: String, _ err: String) -> String { s(
        "\(name) konnte nicht in den Install-Ordner kopiert werden: \(err)",
        "Could not copy \(name) to the Install folder: \(err)"
    ) }

    // MARK: - DebugLog, AppState

    static var logAppStarted: String { s("=== HotSync gestartet ===", "=== HotSync started ===") }
    static var logSetupStarted: String { s("AppState.setup() gestartet", "AppState.setup() started") }
}
