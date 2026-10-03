import Foundation

/// A selection in a list as in the Finder: a click selects one item,
/// shift-click the range from the last clicked item, command-click adds or
/// removes one item.
public struct ListSelection<ID: Hashable>: Equatable, Sendable where ID: Sendable {
    public private(set) var selected: Set<ID> = []
    /// the item a shift-click range starts from
    public private(set) var anchor: ID?

    public init() {}

    public enum Modifier: Sendable {
        case none, extend, toggle
    }

    /// - Parameters:
    ///   - id: the clicked item
    ///   - order: all items in the order shown, for a range
    public mutating func click(_ id: ID, modifier: Modifier, order: [ID]) {
        switch modifier {
        case .none:
            selected = [id]
            anchor = id
        case .toggle:
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
            }
            anchor = id
        case .extend:
            guard let anchor, let from = order.firstIndex(of: anchor),
                  let to = order.firstIndex(of: id) else {
                selected = [id]
                self.anchor = id
                return
            }
            // the range replaces the previous one, as in the Finder
            selected = Set(order[min(from, to)...max(from, to)])
        }
    }

    /// What an action on `id` (drag, context menu) applies to: the whole
    /// selection if `id` is part of it, otherwise `id` alone.
    public func targets(for id: ID, order: [ID]) -> [ID] {
        selected.contains(id) ? order.filter { selected.contains($0) } : [id]
    }

    /// Drops items that no longer exist.
    public mutating func retain(_ ids: Set<ID>) {
        selected.formIntersection(ids)
        if let anchor, !ids.contains(anchor) { self.anchor = nil }
    }
}
