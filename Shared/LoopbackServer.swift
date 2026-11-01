import Foundation

/// In-process stand-in for the backend: the executable specification of the PRD pairing/ingest rules
/// (AT-15 to AT-18, AT-40, AT-44). Used by tests and dev builds only; it does not cross devices.
actor LoopbackServer {
    struct Unit: Equatable, Sendable { var deviceID: UUID; var unitCode: String; var businessName: String; var deviceModel = "" }

    private struct Token { var unit: Unit; var expiresAt: Date; var used = false }
    private struct Credential { var unit: Unit; var installationID: UUID; var revoked = false }

    private var tokens: [String: Token] = [:]            // by code hash; the plain code is never stored
    private var credentials: [String: Credential] = [:]  // by credential hash
    private var seen = Set<UUID>()
    private var latest: [UUID: LocationSample] = [:]
    private var log: [InboundSample] = []
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) { self.now = now }

    /// Owner side: a code bound to one unit of one business.
    func issue(for unit: Unit, lifetime: TimeInterval = PairingCode.lifetime) -> String {
        let code = PairingCode.generate()
        tokens[PairingCode.hash(code)] = Token(unit: unit, expiresAt: now().addingTimeInterval(lifetime))
        return code
    }

    func claim(code: String, installationID: UUID = UUID()) throws -> PairingClaim {
        // ponytail: no attempt throttling here; a real backend must rate-limit claims per installation.
        guard let normalized = PairingCode.normalize(code), var t = tokens[PairingCode.hash(normalized)] else { throw TransportError.invalidCode }
        guard !t.used else { throw TransportError.alreadyUsed }
        guard now() < t.expiresAt else { throw TransportError.expired }
        t.used = true
        tokens[PairingCode.hash(normalized)] = t
        let credential = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        credentials[PairingCode.hash(credential)] = Credential(unit: t.unit, installationID: installationID)
        return PairingClaim(deviceID: t.unit.deviceID, unitCode: t.unit.unitCode, businessName: t.unit.businessName,
                              deviceModel: t.unit.deviceModel, credential: credential)
    }

    func upload(_ batch: [LocationSample], credential: String) throws -> [UUID] {
        guard let c = credentials[PairingCode.hash(credential)], !c.revoked else { throw TransportError.unauthorized }
        var acked: [UUID] = []
        for s in batch {
            acked.append(s.id)
            log.append(InboundSample(deviceID: c.unit.deviceID, installationID: c.installationID, sample: s, receivedAt: now()))
            guard !seen.contains(s.id), SampleValidator.check(s, now: now()) == .valid else { continue }
            seen.insert(s.id)
            if let l = latest[c.unit.deviceID], l.measuredAt >= s.measuredAt { continue }   // never roll the snapshot back (AT-18)
            latest[c.unit.deviceID] = s
        }
        return acked
    }

    func revoke(credential: String) throws {
        let key = PairingCode.hash(credential)
        guard credentials[key] != nil else { throw TransportError.unauthorized }
        credentials[key]?.revoked = true
    }

    func lastLocation(deviceID: UUID) -> LocationSample? { latest[deviceID] }

    // Owner side
    func inboundBatch() -> InboundBatch {
        InboundBatch(samples: log, revokedInstallations: Set(credentials.values.filter(\.revoked).map(\.installationID)))
    }
    func revokeUnit(deviceID: UUID) {
        for k in credentials.keys where credentials[k]?.unit.deviceID == deviceID { credentials[k]?.revoked = true }
    }
}

struct LoopbackTransport: TrackerTransport {
    let server: LoopbackServer
    func claim(code: String, installationID: UUID) async throws -> PairingClaim { try await server.claim(code: code, installationID: installationID) }
    func upload(_ batch: [LocationSample], credential: String) async throws -> [UUID] { try await server.upload(batch, credential: credential) }
    func revoke(credential: String) async throws { try await server.revoke(credential: credential) }
}

struct LoopbackOwner: OwnerGateway {
    let server: LoopbackServer
    let now: @Sendable () -> Date
    init(server: LoopbackServer, now: @escaping @Sendable () -> Date = { .now }) { self.server = server; self.now = now }
    func issuePairing(for unit: PairingUnit) async throws -> IssuedCode {
        let code = await server.issue(for: .init(deviceID: unit.deviceID, unitCode: unit.unitCode, businessName: unit.businessName, deviceModel: unit.deviceModel))
        return IssuedCode(code: code, expiresAt: now().addingTimeInterval(PairingCode.lifetime))
    }
    func inbound() async throws -> InboundBatch { await server.inboundBatch() }
    func revoke(deviceID: UUID) async throws { await server.revokeUnit(deviceID: deviceID) }
}
