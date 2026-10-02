import Foundation
import HotSyncCore
import IOKit
import IOKit.serial
import Observation

/// Kennt die Anschlüsse, an denen ein Palm syncen kann, und wann sie zuletzt
/// etwas gemeldet haben - damit man beim Zuweisen sieht: "das habe ich eben
/// angesteckt".
///
/// - Seriell: Ein USB-Seriell-Adapter erscheint als /dev/cu.…, sobald er
///   steckt - auch ohne Palm. IOKit meldet das Ein- und Ausstecken, daher
///   "Kabel verbunden um 10:12".
/// - USB: Ein Palm erscheint erst während des HotSyncs auf dem Bus; ein
///   USB-Cradle selbst ist unsichtbar. Hier gibt es nur "zuletzt gemeldet:
///   m515 um 10:15" aus den Sitzungen.
@Observable
final class PortMonitor {

    struct SerialPort: Identifiable, Equatable {
        /// Callout-Pfad, z. B. /dev/cu.usbserial-A1
        let id: String
        /// nil: steckte schon beim Programmstart, Zeitpunkt unbekannt
        let connectedAt: Date?

        var name: String { (id as NSString).lastPathComponent }
    }

    struct Sighting: Equatable {
        let user: PalmUser
        let date: Date
    }

    private(set) var serialPorts: [SerialPort] = []
    /// Letzter Palm je Anschluss ("usb:" oder Pfad), aus den Sitzungen
    private(set) var lastSeen: [String: Sighting] = [:]

    /// Ein serieller Adapter kam oder ging - AppState verteilt die Anschlüsse neu.
    @ObservationIgnored var onChange: (() -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    /// Ports, die beim Start schon steckten, bekommen keinen Zeitstempel.
    private var startupDone = false

    func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching(kIOSerialBSDServiceValue),
            serialAdded, refcon, &addedIterator)
        handleAdded(addedIterator)

        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, IOServiceMatching(kIOSerialBSDServiceValue),
            serialRemoved, refcon, &removedIterator)
        handleRemoved(removedIterator)

        startupDone = true
    }

    func isConnected(_ port: String) -> Bool {
        port == SyncTab.usbPort || serialPorts.contains { $0.id == port }
    }

    func serialPort(_ path: String) -> SerialPort? {
        serialPorts.first { $0.id == path }
    }

    /// Von den Sitzungen: dieser Palm hat sich eben an diesem Anschluss gemeldet.
    func recordSighting(_ user: PalmUser, on port: String) {
        lastSeen[port] = Sighting(user: user, date: Date())
    }

    // MARK: - IOKit

    fileprivate func handleAdded(_ iterator: io_iterator_t) {
        defer { if startupDone { onChange?() } }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = calloutPath(service), isUSBAdapter(service) else { continue }
            serialPorts.removeAll { $0.id == path }
            serialPorts.append(SerialPort(id: path, connectedAt: startupDone ? Date() : nil))
            serialPorts.sort { $0.id < $1.id }
            if startupDone {
                DebugLog.shared.log(L10n.logSerialConnected((path as NSString).lastPathComponent), source: "Port")
            }
        }
    }

    fileprivate func handleRemoved(_ iterator: io_iterator_t) {
        defer { if startupDone { onChange?() } }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let path = calloutPath(service) else { continue }
            if serialPorts.contains(where: { $0.id == path }) {
                serialPorts.removeAll { $0.id == path }
                DebugLog.shared.log(L10n.logSerialDisconnected((path as NSString).lastPathComponent), source: "Port")
            }
        }
    }

    private func calloutPath(_ service: io_object_t) -> String? {
        IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// Nur Adapter am USB zählen: Bluetooth-Incoming-Port, debug-console &
    /// Co. sind auch serielle Geräte, aber nie ein Cradle. Ein USB-Adapter hat
    /// irgendwo über sich ein Gerät mit idVendor.
    private func isUSBAdapter(_ service: io_object_t) -> Bool {
        IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) != nil
    }

    deinit {
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }
}

private func serialAdded(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon else { return }
    Unmanaged<PortMonitor>.fromOpaque(refcon).takeUnretainedValue().handleAdded(iterator)
}

private func serialRemoved(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon else { return }
    Unmanaged<PortMonitor>.fromOpaque(refcon).takeUnretainedValue().handleRemoved(iterator)
}
