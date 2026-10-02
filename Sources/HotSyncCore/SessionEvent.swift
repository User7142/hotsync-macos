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
    case connected(PalmUser, romVersion: UInt32)
    case installing(file: String)
    case progress(bytes: Int)
    case installed(file: String, bytes: Int)
    case failed(file: String, InstallFailure)
    case userWritten(PalmUser)
    case finished
    case error(stage: String, message: String)

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
            return .connected(PalmUser(name: name, userId: userId), romVersion: l.romVersion ?? 0)
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
        case "finished":
            return .finished
        case "error":
            return .error(stage: l.stage ?? "", message: l.message ?? "")
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
