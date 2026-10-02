import Foundation

/// A profile as far as the identity check is concerned.
public struct ProfileIdentity: Equatable, Sendable {
    public let id: UUID
    public let userId: UInt32

    public init(id: UUID, userId: UInt32) {
        self.id = id
        self.userId = userId
    }
}

/// What a session does with the Palm that connected.
///
/// The user ID is the identity: it is set once on the Palm (first HotSync)
/// and kept across renames. The user name is only shown.
public enum PalmAdmission: Equatable, Sendable {
    /// the Palm belongs to this profile: install its queue
    case install(profile: UUID)
    /// a Palm without a user in a session for this profile: write the
    /// profile's identity to the Palm, then install its queue
    case adopt(profile: UUID)
    /// the Palm belongs to another profile than the one the session waits
    /// for: install nothing
    case wrongPalm(expected: UUID, found: UUID)
    /// no profile knows this Palm: install nothing
    case unknown
    /// a Palm without a user that no session was waiting for: install
    /// nothing (it is not clear which profile it should become)
    case blank

    /// - Parameters:
    ///   - expected: the profile the session waits for (a tab started by
    ///     hand or by a chain), nil for a port listener that serves every
    ///     profile on its port
    ///   - candidates: the profiles the session may serve - for a port
    ///     listener the profiles of all tabs on that port
    ///   - profiles: all profiles, to name the owner of a wrong Palm
    public static func decide(
        user: PalmUser,
        expected: UUID?,
        candidates: [ProfileIdentity],
        profiles: [ProfileIdentity]
    ) -> PalmAdmission {
        if user.isBlank {
            if let expected { return .adopt(profile: expected) }
            return .blank
        }
        let owner = profiles.first { $0.userId == user.userId }
        if let expected {
            guard let owner else { return .unknown }
            return owner.id == expected
                ? .install(profile: expected)
                : .wrongPalm(expected: expected, found: owner.id)
        }
        guard let owner, candidates.contains(where: { $0.id == owner.id }) else {
            return .unknown
        }
        return .install(profile: owner.id)
    }
}
