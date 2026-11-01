import Foundation

struct PairingUnit: Equatable, Sendable {
    var deviceID: UUID
    var unitCode: String
    var businessName: String
    var deviceModel: String
}

struct IssuedCode: Equatable, Sendable {
    var code: String               // plain, shown once; only its hash is stored remotely
    var expiresAt: Date            // judged by the backend's clock, not the phone's
}

/// One uploaded point as the owner side sees it.
struct InboundSample: Equatable, Sendable {
    var deviceID: UUID
    var installationID: UUID
    var sample: LocationSample
    var receivedAt: Date
}

struct InboundBatch: Equatable, Sendable {
    var samples: [InboundSample] = []
    var revokedInstallations: Set<UUID> = []
}

/// The owner's door to the backend (issue codes, read what trackers sent, revoke).
/// CloudKit has no server code, so the admin app applies the ingest rules itself via `LocationAggregator`.
protocol OwnerGateway: Sendable {
    func issuePairing(for unit: PairingUnit) async throws -> IssuedCode
    func inbound() async throws -> InboundBatch
    func revoke(deviceID: UUID) async throws
}

struct UnconfiguredOwnerGateway: OwnerGateway {
    func issuePairing(for unit: PairingUnit) async throws -> IssuedCode { throw TransportError.notConfigured }
    func inbound() async throws -> InboundBatch { throw TransportError.notConfigured }
    func revoke(deviceID: UUID) async throws { throw TransportError.notConfigured }
}

/// Reader-side rules (PRD 8.1, AT-18, AT-44): the single place that decides which uploaded points count.
enum LocationAggregator {
    static let retention: TimeInterval = Double(ConsentText.retentionDays) * 86_400

    /// Drops revoked installations, invalid points, points already stored, repeats inside the batch, and anything past retention.
    /// Out-of-order points are kept as history; "latest" is always the newest `measuredAt`, so it can never roll back.
    static func accept(_ inbound: [InboundSample], revoked: Set<UUID>, knownSampleIDs: Set<UUID>, now: Date) -> [InboundSample] {
        var seen = knownSampleIDs
        return inbound.filter { i in
            guard !revoked.contains(i.installationID),
                  SampleValidator.check(i.sample, now: now) == .valid,
                  now.timeIntervalSince(i.sample.measuredAt) <= retention,
                  seen.insert(i.sample.id).inserted else { return false }
            return true
        }
        .sorted { $0.sample.measuredAt < $1.sample.measuredAt }
    }
}
