import Foundation
import IOKit
import IOKit.usb
import Observation

@Observable
final class USBMonitor {

    private(set) var isDeviceConnected = false

    var onDeviceConnected: (() -> Void)?

    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    private static let palmVendorID: Int = 0x0830

    func startMonitoring() {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = Self.palmVendorID

        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        // Retain self für die C-Callbacks
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Device attached
        let matchForAdd = matchingDict.mutableCopy() as! NSMutableDictionary
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOMatchedNotification,
            matchForAdd,
            deviceAdded,
            selfPtr,
            &addedIterator
        )
        // Initiale Geräte abarbeiten
        drainIterator(addedIterator, connected: true)

        // Device removed
        let matchForRemove = matchingDict.mutableCopy() as! NSMutableDictionary
        IOServiceAddMatchingNotification(
            notifyPort,
            kIOTerminatedNotification,
            matchForRemove,
            deviceRemoved,
            selfPtr,
            &removedIterator
        )
        drainIterator(removedIterator, connected: false)
    }

    func stopMonitoring() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
    }

    fileprivate func drainIterator(_ iterator: io_iterator_t, connected: Bool) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
            if connected {
                isDeviceConnected = true
                onDeviceConnected?()
            }
        }
        if !connected {
            isDeviceConnected = false
        }
    }

    deinit {
        stopMonitoring()
    }
}

// IOKit C-Callback Funktionen
private func deviceAdded(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon else { return }
    let monitor = Unmanaged<USBMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.drainIterator(iterator, connected: true)
}

private func deviceRemoved(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon else { return }
    let monitor = Unmanaged<USBMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.drainIterator(iterator, connected: false)
}
