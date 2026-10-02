import Foundation

/// Why the Palm did not take a file.
public enum InstallFailure: Equatable, Sendable {
    /// dlpRespErrAlreadyExists: a database of that name is on the Palm and
    /// could not be replaced - it is protected (e.g. a system extension
    /// that is active, like DateFix) or in use.
    case protectedOnPalm
    /// dlpRespErrDatabaseOpen: the application is open on the Palm.
    case openOnPalm
    /// dlpRespErrReadOnly: in ROM or read-only.
    case readOnly
    /// dlpRespErrNotEnoughSpace, or the file is larger than the free memory
    case notEnoughSpace
    /// dlpRespErrLimitExceeded
    case tooLarge
    /// the file could not be read on the Mac.
    case unreadableFile
    /// another Data Link Protocol error
    case palmError(code: Int)
    /// the session ended (connection lost, cancelled) before the file
    case notConfirmed

    /// Maps a Palm OS DLP error code (`pi_palmos_error`) to a reason.
    public static func fromPalmOSError(_ code: Int) -> InstallFailure {
        switch code {
        case 7:  return .openOnPalm
        case 9:  return .protectedOnPalm
        case 15: return .readOnly
        case 16: return .notEnoughSpace
        case 17: return .tooLarge
        default: return .palmError(code: code)
        }
    }
}
