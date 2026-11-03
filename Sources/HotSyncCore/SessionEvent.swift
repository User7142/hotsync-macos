import Foundation

/// The identity a Palm reports when it connects: user name and user ID as
/// set by the first HotSync. A Palm that was never synced (or hard reset)
/// reports user ID 0 and usually an empty name.
public struct PalmUser: Equatable, Sendable, Codable {
    public let name: String
    public let userId: UInt32

    public init(name: String, userId: UInt32) {
        self.name = name
        self.userId = userId
    }

    /// true for a Palm without a user - it takes the identity of the
    /// profile it is synced with.
    public var isBlank: Bool { userId == 0 }
}

/// One line of `hotsync-session` output (a JSON object per line).
public enum SessionEvent: Equatable, Sendable {
    case listening(port: String)
    case timeout
    /// `dateFixStartYear`: DateFix is on, the Palm's dates and clock are
    /// shifted by that year minus 1904
    case connected(PalmUser, romVersion: UInt32, dateFixStartYear: Int? = nil)
    case installing(file: String)
    case progress(bytes: Int)
    case installed(file: String, bytes: Int)
    case failed(file: String, InstallFailure)
    case userWritten(PalmUser)
    /// backup of the RAM databases into this directory: `total` databases
    case backupStarted(directory: String, total: Int)
    /// database `index` of `total` (file name as saved) is being fetched
    case backingUp(file: String, index: Int, total: Int)
    /// database `index` did not change since the last backup: skipped
    case backupUnchanged(file: String, index: Int)
    case backedUp(file: String, bytes: Int)
    case backupFailed(file: String, palmOSError: Int)
    case backupFinished(saved: Int, unchanged: Int, failed: Int)
    /// ROM dump into `file` (name in the folder given): `total` bytes of
    /// Palm OS `version`
    case romStarted(file: String, version: String, total: Int)
    case romProgress(bytes: Int)
    case romFinished(file: String, bytes: Int)
    /// Palm OS 5 and later: the ROM cannot be read over HotSync
    case romUnsupported(version: String)
    case finished
    case error(stage: String, message: String)

    // Record access for the PIM sync (one database open at a time)

    /// right after `connected`: which PC synced last (0: none known) and when
    case syncInfo(lastSyncPC: UInt32, lastSyncDate: Date?)
    case dbOpened(name: String, records: Int)
    case dbClosed
    case appInfo(Data)
    case appInfoWritten(bytes: Int)
    /// one record: flags in `attributes` (dlpRecAttr*: deleted 0x80, dirty
    /// 0x40, busy 0x20, secret 0x10, archived 0x08), category separate, the
    /// data as it is on the Palm (empty for a deleted one)
    case record(id: UInt32, index: Int, attributes: UInt8, category: Int, data: Data)
    /// all records asked for have been sent
    case recordsDone(count: Int, modifiedOnly: Bool)
    /// `id` is the one the Palm gave the record (the one asked for, or new)
    case recordWritten(id: UInt32, bytes: Int)
    case recordDeleted(id: UInt32)
    case flagsReset
    case cleanedUp
    case syncInfoWritten(pcId: UInt32, date: Date)
    /// the Palm's clock was set to the Mac's time
    case timeSet(Date)
    /// this Mac is the Palm's primary PC for network HotSync now
    case netSyncSet(address: String, name: String)

    private struct Line: Decodable {
        let event: String
        let port: String?
        let user: String?
        let userId: UInt32?
        let romVersion: UInt32?
        let file: String?
        let bytes: Int?
        let reason: String?
        let palmOSError: Int?
        let stage: String?
        let message: String?
        let directory: String?
        let index: Int?
        let total: Int?
        let saved: Int?
        let unchanged: Int?
        let failed: Int?
        let version: String?
        let lastSyncPC: UInt32?
        let lastSyncDate: Int?
        let name: String?
        let records: Int?
        let data: String?
        let id: UInt32?
        let attrs: Int?
        let category: Int?
        let count: Int?
        let modifiedOnly: Int?
        let pcId: UInt32?
        let date: Int?
        let address: String?
        let dateFixStartYear: Int?
    }

    /// Reads one output line; nil for anything that is not a known event
    /// (the tool only prints events, so nil means a broken line).
    public static func parse(_ line: String) -> SessionEvent? {
        guard let data = line.data(using: .utf8),
              let l = try? JSONDecoder().decode(Line.self, from: data) else {
            return nil
        }
        switch l.event {
        case "listening":
            return .listening(port: l.port ?? "")
        case "timeout":
            return .timeout
        case "connected":
            guard let name = l.user, let userId = l.userId else { return nil }
            return .connected(PalmUser(name: name, userId: userId), romVersion: l.romVersion ?? 0, dateFixStartYear: l.dateFixStartYear)
        case "installing":
            guard let file = l.file else { return nil }
            return .installing(file: file)
        case "progress":
            return .progress(bytes: l.bytes ?? 0)
        case "installed":
            guard let file = l.file else { return nil }
            return .installed(file: file, bytes: l.bytes ?? 0)
        case "failed":
            guard let file = l.file else { return nil }
            return .failed(file: file, failure(reason: l.reason, palmOSError: l.palmOSError))
        case "userWritten":
            guard let name = l.user, let userId = l.userId else { return nil }
            return .userWritten(PalmUser(name: name, userId: userId))
        case "backupStarted":
            guard let directory = l.directory else { return nil }
            return .backupStarted(directory: directory, total: l.total ?? 0)
        case "backingUp":
            guard let file = l.file, let index = l.index else { return nil }
            return .backingUp(file: file, index: index, total: l.total ?? 0)
        case "backupUnchanged":
            guard let file = l.file, let index = l.index else { return nil }
            return .backupUnchanged(file: file, index: index)
        case "backedUp":
            guard let file = l.file else { return nil }
            return .backedUp(file: file, bytes: l.bytes ?? 0)
        case "backupFailed":
            guard let file = l.file else { return nil }
            return .backupFailed(file: file, palmOSError: l.palmOSError ?? 0)
        case "backupFinished":
            return .backupFinished(saved: l.saved ?? 0, unchanged: l.unchanged ?? 0, failed: l.failed ?? 0)
        case "romStarted":
            guard let file = l.file, let version = l.version, let total = l.total else { return nil }
            return .romStarted(file: file, version: version, total: total)
        case "romProgress":
            guard let bytes = l.bytes else { return nil }
            return .romProgress(bytes: bytes)
        case "romFinished":
            guard let file = l.file, let bytes = l.bytes else { return nil }
            return .romFinished(file: file, bytes: bytes)
        case "romUnsupported":
            return .romUnsupported(version: l.version ?? "")
        case "finished":
            return .finished
        case "error":
            return .error(stage: l.stage ?? "", message: l.message ?? "")
        case "syncInfo":
            let date = l.lastSyncDate.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
            return .syncInfo(lastSyncPC: l.lastSyncPC ?? 0, lastSyncDate: date)
        case "dbOpened":
            guard let name = l.name else { return nil }
            return .dbOpened(name: name, records: l.records ?? -1)
        case "dbClosed":
            return .dbClosed
        case "appInfo":
            guard let data = l.data.flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return .appInfo(data)
        case "appInfoWritten":
            return .appInfoWritten(bytes: l.bytes ?? 0)
        case "record":
            guard let id = l.id, let data = l.data.flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return .record(id: id, index: l.index ?? -1, attributes: UInt8(clamping: l.attrs ?? 0) & 0xF8,
                           category: l.category ?? 0, data: data)
        case "recordsDone":
            return .recordsDone(count: l.count ?? 0, modifiedOnly: (l.modifiedOnly ?? 0) != 0)
        case "recordWritten":
            guard let id = l.id else { return nil }
            return .recordWritten(id: id, bytes: l.bytes ?? 0)
        case "recordDeleted":
            guard let id = l.id else { return nil }
            return .recordDeleted(id: id)
        case "flagsReset":
            return .flagsReset
        case "cleanedUp":
            return .cleanedUp
        case "syncInfoWritten":
            guard let pcId = l.pcId, let date = l.date else { return nil }
            return .syncInfoWritten(pcId: pcId, date: Date(timeIntervalSince1970: TimeInterval(date)))
        case "timeSet":
            guard let date = l.date else { return nil }
            return .timeSet(Date(timeIntervalSince1970: TimeInterval(date)))
        case "netSyncSet":
            guard let address = l.address else { return nil }
            return .netSyncSet(address: address, name: l.name ?? "")
        default:
            return nil
        }
    }

    private static func failure(reason: String?, palmOSError: Int?) -> InstallFailure {
        switch reason {
        case "unreadableFile": return .unreadableFile
        case "notEnoughSpace": return .notEnoughSpace
        default: return InstallFailure.fromPalmOSError(palmOSError ?? 0)
        }
    }
}
