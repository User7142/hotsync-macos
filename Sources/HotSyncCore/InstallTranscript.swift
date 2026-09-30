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
    /// dlpRespErrNotEnoughSpace
    case notEnoughSpace
    /// dlpRespErrLimitExceeded
    case tooLarge
    /// pilot-xfer could not read the file on the Mac.
    case unreadableFile
    /// another Data Link Protocol error
    case palmError(code: Int, message: String)
    /// an error pilot-xfer printed without a Palm OS code
    case other(String)
    /// the session ended (connection lost, cancelled) before the file
    case notConfirmed

    /// Reads "ERROR: pi_file_install failed (-301, PalmOS 0x0009)."
    public static func parse(_ line: String) -> InstallFailure {
        guard let range = line.range(of: "PalmOS 0x") else {
            return .other(line)
        }
        let hex = line[range.upperBound...].prefix { $0.isHexDigit }
        guard let code = Int(hex, radix: 16) else { return .other(line) }
        switch code {
        case 7:  return .openOnPalm
        case 9:  return .protectedOnPalm
        case 15: return .readOnly
        case 16: return .notEnoughSpace
        case 17: return .tooLarge
        default: return .palmError(code: code, message: line)
        }
    }
}

/// Reads the output of `pilot-xfer -i file1 file2 ...`:
///
///     stdout  Installing 'a.prc'... Installing 'a.prc' ... (1234 bytes)   1 KiB total.
///     stderr  ERROR: pi_file_install failed (-301, PalmOS 0x0009).
///     stderr  ERROR: Unable to open '/path/b.prc'!
///     stdout  Thank you for using pilot-link.
///
/// "KiB total." follows only a successful transfer - only then a file
/// counts as installed.
///
/// stdout reaches us block-buffered and stderr unbuffered, so an error line
/// usually arrives *before* the "Installing" of its file. Each stream keeps
/// its own order, though, and pilot-xfer installs the files in the order of
/// its arguments: the n-th error belongs to the n-th file that was neither
/// confirmed nor unreadable.
public final class InstallTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private let expected: [String]
    private var currentName: String?
    private var confirmedNames: Set<String> = []
    private var unreadableNames: Set<String> = []
    private var errors: [InstallFailure] = []
    private var ended = false
    private var output = false

    public init(expected: [String]) {
        self.expected = expected
    }

    public var confirmed: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return confirmedNames
    }

    public var current: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentName
    }

    public var sawOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return output
    }

    /// The session is over: pilot-xfer said goodbye, or every file has an
    /// outcome.
    public var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        let outcomes = Set(expected).intersection(confirmedNames.union(unreadableNames)).count
            + errors.count
        return ended || outcomes >= expected.count
    }

    /// Why each file that was not confirmed failed.
    public var failures: [String: InstallFailure] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: InstallFailure] = [:]
        var pending = errors[...]
        for name in expected where !confirmedNames.contains(name) {
            if unreadableNames.contains(name) {
                result[name] = .unreadableFile
            } else if let error = pending.popFirst() {
                result[name] = error
            } else {
                result[name] = .notConfirmed
            }
        }
        return result
    }

    public func consume(_ line: String, fromStderr: Bool) {
        lock.lock()
        defer { lock.unlock() }
        output = true

        if fromStderr {
            if let path = Self.quoted(in: line, after: "Unable to open '") {
                unreadableNames.insert((path as NSString).lastPathComponent)
            } else if line.contains("ERROR") {
                errors.append(InstallFailure.parse(line))
            }
        } else {
            if let name = Self.quoted(in: line, after: "Installing '") {
                currentName = name
            }
            if line.contains("KiB total."), let name = currentName {
                confirmedNames.insert(name)
                currentName = nil
            }
        }
        if line.contains("Thank you for using pilot-link") || line.contains("CANCEL") {
            ended = true
        }
    }

    private static func quoted(in line: String, after prefix: String) -> String? {
        guard let start = line.range(of: prefix, options: .backwards),
              let end = line[start.upperBound...].firstIndex(of: "'") else { return nil }
        return String(line[start.upperBound..<end])
    }
}
