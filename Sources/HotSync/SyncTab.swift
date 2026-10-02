import Foundation
import Observation

/// Ein Tab: ein Palm-Profil an einem Anschluss - "m515 · USB",
/// "IIIx · cu.usbserial-A1". Derselbe Palm kann mehrere Tabs haben (einmal
/// USB, einmal seriell); die Warteschlange gehört dem Profil, nicht dem Tab.
struct SyncTab: Codable, Identifiable, Equatable {
    let id: UUID
    var profileId: UUID
    /// "usb:" oder ein serieller Callout-Pfad wie /dev/cu.usbserial-A1
    var port: String
    /// Baudrate für serielle Anschlüsse (PILOTRATE); bei USB ohne Bedeutung
    var baudRate: Int
    /// Lauscht von selbst, sobald der Anschluss frei ist - wie HotSync bis
    /// 1.0.x. Ohne: nur per Start-Knopf oder als Schritt einer Kette.
    var autoListen: Bool

    init(id: UUID = UUID(), profileId: UUID, port: String, baudRate: Int = SyncTab.defaultBaudRate,
         autoListen: Bool) {
        self.id = id
        self.profileId = profileId
        self.port = port
        self.baudRate = baudRate
        self.autoListen = autoListen
    }

    static let usbPort = "usb:"
    /// Schnell genug für Installationen, und jedes serielle Cradle (ab Palm
    /// III) kann es; 115200 schaffen nicht alle Kabel/Adapter stabil.
    static let defaultBaudRate = 57600
    static let baudRates = [9600, 19200, 38400, 57600, 115200]

    var isUSB: Bool { port == Self.usbPort }

    /// Kurzname des Anschlusses für Tab-Titel: "USB", "cu.usbserial-A1".
    var portLabel: String {
        isUSB ? "USB" : (port as NSString).lastPathComponent
    }
}

/// Eine Kette: Tabs, die nacheinander syncen - "wenn A fertig ist, B, dann C".
struct SyncChain: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var steps: [UUID]

    init(id: UUID = UUID(), name: String, steps: [UUID] = []) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

/// Speichert Tabs und Ketten in ~/HotSync (tabs.json, chains.json) - neben
/// profiles.json, damit alles zu einem Palm-Setup an einer Stelle liegt.
@Observable
final class TabStore {
    private(set) var tabs: [SyncTab] = []
    private(set) var chains: [SyncChain] = []

    private let tabsURL: URL
    private let chainsURL: URL

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("HotSync")
        tabsURL = dir.appendingPathComponent("tabs.json")
        chainsURL = dir.appendingPathComponent("chains.json")
        tabs = load(tabsURL) ?? []
        chains = load(chainsURL) ?? []
    }

    /// true, wenn es noch keine tabs.json gibt (erster Start von 1.1).
    var isFirstRun: Bool {
        !FileManager.default.fileExists(atPath: tabsURL.path)
    }

    /// Bis 1.0.x lauschte HotSync für das aktive Profil an USB. Jedes Profil
    /// bekommt deshalb einen USB-Tab, der wie bisher von selbst lauscht.
    func migrate(profiles: [DeviceProfile]) {
        guard isFirstRun else { return }
        tabs = profiles.map { SyncTab(profileId: $0.id, port: SyncTab.usbPort, autoListen: true) }
        saveTabs()
        DebugLog.shared.log(L10n.logTabsMigrated(tabs.count), source: "App")
    }

    func tab(_ id: UUID) -> SyncTab? {
        tabs.first { $0.id == id }
    }

    func chain(_ id: UUID) -> SyncChain? {
        chains.first { $0.id == id }
    }

    func save(_ tab: SyncTab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        saveTabs()
    }

    /// Löscht einen Tab und nimmt ihn aus allen Ketten.
    func deleteTab(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        saveTabs()
        removeFromChains { $0 == id }
    }

    /// Ein Profil wurde gelöscht: seine Tabs verschwinden mit.
    func deleteTabs(ofProfile profileId: UUID) {
        let ids = Set(tabs.filter { $0.profileId == profileId }.map(\.id))
        guard !ids.isEmpty else { return }
        tabs.removeAll { ids.contains($0.id) }
        saveTabs()
        removeFromChains { ids.contains($0) }
    }

    func save(_ chain: SyncChain) {
        if let index = chains.firstIndex(where: { $0.id == chain.id }) {
            chains[index] = chain
        } else {
            chains.append(chain)
        }
        saveChains()
    }

    func deleteChain(_ id: UUID) {
        chains.removeAll { $0.id == id }
        saveChains()
    }

    private func removeFromChains(where shouldRemove: (UUID) -> Bool) {
        var changed = false
        for index in chains.indices {
            let before = chains[index].steps.count
            chains[index].steps.removeAll(where: shouldRemove)
            changed = changed || chains[index].steps.count != before
        }
        if changed { saveChains() }
    }

    // MARK: - Dateien

    private func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            DebugLog.shared.log(L10n.logLoadError("\(url.lastPathComponent): \(error)"), source: "App")
            return nil
        }
    }

    private func saveTabs() { write(tabs, to: tabsURL) }
    private func saveChains() { write(chains, to: chainsURL) }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            DebugLog.shared.log(L10n.logSaveError("\(url.lastPathComponent): \(error)"), source: "App")
        }
    }
}
