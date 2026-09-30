import Foundation

/// The header of a Palm database file (.prc, .pdb, .pqa), as pilot-xfer
/// sends it to the Palm. Checked before a file is offered for a HotSync,
/// so the queue can tell right away whether a file can be installed.
///
/// Layout (Palm File Format Specification, big-endian):
///
///     0  name[32]         NUL-terminated
///    32  attributes       UInt16, bit 0 = resource database (.prc)
///    34  version          UInt16
///    36  creation/modification/backup date, modification number,
///        appInfo/sortInfo offsets
///    60  type[4]
///    64  creator[4]
///    68  uniqueIDSeed, nextRecordListID
///    76  numRecords       UInt16
///    78  record list: 10 bytes per resource, 8 bytes per record
public struct PalmDatabaseFile: Equatable, Sendable {
    public let name: String
    public let type: String
    public let creator: String
    public let isResourceDatabase: Bool
    public let recordCount: Int

    public static let supportedExtensions: Set<String> = ["prc", "pdb", "pqa"]
    static let headerSize = 78

    public enum Problem: Error, Equatable, Sendable {
        case unsupportedExtension(String)
        case unreadable
        case tooSmall
        case invalidName
        /// .prc must be a resource database, .pdb a record database
        case kindMismatch(expectedResource: Bool)
        case truncated
    }

    public static func inspect(url: URL) -> Result<PalmDatabaseFile, Problem> {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return .failure(.unsupportedExtension(ext))
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return .failure(.unreadable)
        }
        return inspect(data: data, fileExtension: ext)
    }

    public static func inspect(data: Data, fileExtension: String) -> Result<PalmDatabaseFile, Problem> {
        let ext = fileExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return .failure(.unsupportedExtension(ext))
        }
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { return .failure(.tooSmall) }

        // name: printable characters up to a NUL within the 32 bytes
        guard let end = bytes[0..<32].firstIndex(of: 0), end > 0,
              bytes[0..<end].allSatisfy({ $0 >= 0x20 }) else {
            return .failure(.invalidName)
        }
        let name = String(decoding: bytes[0..<end], as: UTF8.self)

        let attributes = UInt16(bytes[32]) << 8 | UInt16(bytes[33])
        let isResource = attributes & 0x0001 != 0
        switch ext {
        case "prc" where !isResource:
            return .failure(.kindMismatch(expectedResource: true))
        case "pdb" where isResource, "pqa" where isResource:
            return .failure(.kindMismatch(expectedResource: false))
        default:
            break
        }

        let count = Int(bytes[76]) << 8 | Int(bytes[77])
        let entrySize = isResource ? 10 : 8
        guard headerSize + count * entrySize <= bytes.count else {
            return .failure(.truncated)
        }

        return .success(PalmDatabaseFile(
            name: name,
            type: fourCC(bytes[60..<64]),
            creator: fourCC(bytes[64..<68]),
            isResourceDatabase: isResource,
            recordCount: count
        ))
    }

    private static func fourCC(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes.map { $0 >= 0x20 && $0 < 0x7F ? Character(UnicodeScalar($0)) : "?" })
    }
}
