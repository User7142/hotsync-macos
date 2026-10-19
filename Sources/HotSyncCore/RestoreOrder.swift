import Foundation

/// The order in which a backup goes back onto a Palm, as pilot-xfer
/// restores: of the databases of one creator, the data before the
/// application (an application can look for its data when it is installed),
/// and larger databases before smaller ones, while the Palm's memory is
/// still in one piece.
public enum RestoreOrder {
    public struct Item: Equatable, Sendable {
        public let name: String
        public let type: String
        public let creator: String
        public let size: Int

        public init(name: String, type: String, creator: String, size: Int) {
            self.name = name
            self.type = type
            self.creator = creator
            self.size = size
        }

        var isApplication: Bool { type == "appl" }
    }

    /// Groups of one creator, the group with the largest database first;
    /// in a group the data by size, then the applications by size.
    public static func sorted(_ items: [Item]) -> [Item] {
        let groups = Dictionary(grouping: items, by: \.creator).values.map { group in
            group.sorted { a, b in
                if a.isApplication != b.isApplication { return !a.isApplication }
                if a.size != b.size { return a.size > b.size }
                return a.name < b.name
            }
        }
        return groups
            .sorted { a, b in
                let sizeA = a.map(\.size).max() ?? 0, sizeB = b.map(\.size).max() ?? 0
                if sizeA != sizeB { return sizeA > sizeB }
                return a[0].creator < b[0].creator
            }
            .flatMap { $0 }
    }
}
