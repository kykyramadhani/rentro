import Foundation

struct PairingClaim: Equatable, Sendable {
    var deviceID: UUID
    var unitCode: String
    var businessName: String
    var deviceModel = ""
    var credential: String          // installation-scoped: can only write this unit's samples
}

enum TransportError: Error, Equatable, Sendable {
    case invalidCode, expired, alreadyUsed, unauthorized, notConfigured, noICloudAccount, offline
}

extension TransportError {
    var userMessage: String {
        switch self {
        case .invalidCode: String(localized: "That code isn't valid. Check it and try again.")
        case .expired: String(localized: "This code has expired. Ask the rental business for a new one.")
        case .alreadyUsed: String(localized: "This code was already used. Ask the rental business for a new one.")
        case .unauthorized: String(localized: "The rental business no longer accepts this pairing.")
        case .notConfigured: String(localized: "Pairing isn't available in this build yet.")
        case .noICloudAccount: String(localized: "Sign in to iCloud in Settings, then try again.")
        case .offline: String(localized: "You're offline. Try again when you have a connection.")
        }
    }
}

/// The tracker only ever talks to the owner through this narrow door (PRD 6.2). The CloudKit-backed implementation
/// lives behind it; `LoopbackServer` below defines the rules every implementation must honour.
protocol TrackerTransport: Sendable {
    func claim(code: String, installationID: UUID) async throws -> PairingClaim
    /// IDs the client may drop from its queue (accepted, duplicate or permanently invalid).
    func upload(_ batch: [LocationSample], credential: String) async throws -> [UUID]
    func revoke(credential: String) async throws
}

/// Used where no backend exists yet (release builds before the iCloud container is configured). Fails honestly.
struct UnconfiguredTransport: TrackerTransport {
    func claim(code: String, installationID: UUID) async throws -> PairingClaim { throw TransportError.notConfigured }
    func upload(_ batch: [LocationSample], credential: String) async throws -> [UUID] { throw TransportError.notConfigured }
    func revoke(credential: String) async throws { throw TransportError.notConfigured }
}
