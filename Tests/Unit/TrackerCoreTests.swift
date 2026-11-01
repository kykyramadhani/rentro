import CloudKit
import Foundation
import Testing
@testable import Rentro

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    init(_ t: Date) { self.t = t }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

struct TrackerCoreTests {
    let t0 = Date(timeIntervalSince1970: 1_792_900_000)
    func sample(_ lat: Double = -8.65, _ lon: Double = 115.2, acc: Double = 10, at: Date? = nil, id: UUID = UUID()) -> LocationSample {
        LocationSample(id: id, latitude: lat, longitude: lon, horizontalAccuracyM: acc, measuredAt: at ?? t0)
    }

    // MARK: pairing codes (T01)

    @Test func generatedCodesUseTheUnambiguousAlphabet() {
        for _ in 0..<200 {
            let c = PairingCode.generate()
            #expect(c.count == 8 && c.allSatisfy(PairingCode.alphabet.contains))
            #expect(!c.contains("0") && !c.contains("O") && !c.contains("1") && !c.contains("I"))
        }
    }

    @Test func normalizeAcceptsHumanFormsAndRejectsMalformedInput() {
        #expect(PairingCode.normalize("k7m2-9qxa") == "K7M29QXA")
        #expect(PairingCode.normalize(" K7M2 9QXA ") == "K7M29QXA")
        #expect(PairingCode.normalize("K7M2") == nil)             // too short
        #expect(PairingCode.normalize("K7M2-9QX0") == nil)        // 0 is not in the alphabet
        #expect(PairingCode.normalize("") == nil)
        #expect(PairingCode.display("K7M29QXA") == "K7M2-9QXA")
    }

    @Test func qrPayloadRoundTripsAndForeignPayloadsAreRejected() {
        #expect(PairingCode.fromQR(PairingCode.qrPayload("K7M29QXA")) == "K7M29QXA")
        #expect(PairingCode.fromQR("K7M2-9QXA") == "K7M29QXA")
        #expect(PairingCode.fromQR("https://evil.example/pair?code=K7M2-9QXA") == nil)
        #expect(PairingCode.fromQR("rentro://other?code=K7M2-9QXA") == nil)
        #expect(PairingCode.fromQR("rentro://pair?code=bad") == nil)
    }

    @Test func codesAreStoredAsAHashNeverPlain() {
        let h = PairingCode.hash("K7M29QXA")
        #expect(h.count == 64 && h != "K7M29QXA" && h == PairingCode.hash("K7M29QXA") && h != PairingCode.hash("K7M29QXB"))
    }

    // MARK: sample validation and sampling

    @Test func invalidSamplesAreRejected() {
        #expect(SampleValidator.check(sample(), now: t0) == .valid)
        #expect(SampleValidator.check(sample(91, 0), now: t0) != .valid)
        #expect(SampleValidator.check(sample(0, 181), now: t0) != .valid)
        #expect(SampleValidator.check(sample(.nan, 0), now: t0) != .valid)
        #expect(SampleValidator.check(sample(acc: -1), now: t0) != .valid)
        #expect(SampleValidator.check(sample(acc: 5000), now: t0) != .valid)
        #expect(SampleValidator.check(sample(at: t0.addingTimeInterval(3600)), now: t0) != .valid)
        #expect(SampleValidator.check(sample(at: t0.addingTimeInterval(60)), now: t0) == .valid)   // within clock tolerance
    }

    @Test func samplingRecordsOnMovementOrAfterQuietIntervalOnly() {
        let p = SamplingPolicy()
        let a = sample(-8.65, 115.2, at: t0)
        #expect(p.shouldRecord(previous: nil, candidate: a))
        #expect(!p.shouldRecord(previous: a, candidate: sample(-8.65, 115.2, at: t0.addingTimeInterval(30))))        // still
        #expect(p.shouldRecord(previous: a, candidate: sample(-8.652, 115.2, at: t0.addingTimeInterval(30))))        // ~220 m
        #expect(p.shouldRecord(previous: a, candidate: sample(-8.65, 115.2, at: t0.addingTimeInterval(301))))        // quiet interval
        #expect(!p.shouldRecord(previous: a, candidate: sample(-8.7, 115.3, at: t0.addingTimeInterval(-10))))        // out of order
    }

    @Test func haversineIsRoughlyRight() {
        let d = Geo.distance(sample(-8.65, 115.2), sample(-8.66, 115.2))
        #expect(abs(d - 1112) < 15)      // 0.01 degree of latitude is about 1.11 km
    }

    // MARK: offline queue (T06)

    @Test func queueDedupesCapsExpiresAndAcknowledges() {
        var q = UploadQueue(maxCount: 3, maxAge: 3600)
        let dup = sample(id: UUID())
        q.enqueue(dup, now: t0); q.enqueue(dup, now: t0)
        #expect(q.samples.count == 1)
        for i in 1...4 { q.enqueue(sample(at: t0.addingTimeInterval(Double(i))), now: t0) }
        #expect(q.samples.count == 3)                                           // oldest dropped, never unbounded
        #expect(!q.samples.contains(dup))
        q.prune(now: t0.addingTimeInterval(3601 + 2))                          // two newest are still inside the window
        #expect(q.samples.count == 2)
        q.acknowledge(q.samples.map(\.id))
        #expect(q.samples.isEmpty)
        q.enqueue(sample(), now: t0); q.wipe()
        #expect(q.samples.isEmpty)
    }

    @Test func backoffDoublesAndCaps() {
        #expect(Backoff.delay(attempt: 0) == 5 && Backoff.delay(attempt: 1) == 10 && Backoff.delay(attempt: 3) == 40)
        #expect(Backoff.delay(attempt: 20) == 900)
    }

    // MARK: tracker status (T03, AT-41, AT-42)

    func status(paired: Bool = true, consent: Consent? = nil, auth: OSLocationAuth = .always, enabled: Bool = true,
                ends: Date? = nil, ack: Date? = nil) -> TrackerStatus {
        TrackerStatus.derive(paired: paired, consent: consent, auth: auth, sharingEnabled: enabled, sharingEndsAt: ends, lastUploadAckAt: ack, now: t0)
    }
    var consent: Consent { Consent(version: 1, acceptedAt: t0, revokedAt: nil, businessName: "B", unitCode: "IP-001") }

    @Test func statusTellsTheTruth() {
        let recent = t0.addingTimeInterval(-120), old = t0.addingTimeInterval(-3 * 3600)
        #expect(status(paired: false, consent: consent, ack: recent) == .notPaired)
        #expect(status(consent: nil, ack: recent) == .needsConsent)
        #expect(status(consent: { var c = consent; c.revokedAt = t0; return c }(), ack: recent) == .needsConsent)
        #expect(status(consent: consent, auth: .denied, ack: recent) == .permissionRequired)
        #expect(status(consent: consent, auth: .notDetermined, ack: recent) == .permissionRequired)
        #expect(status(consent: consent, auth: .restricted, ack: recent) == .permissionRequired)
        #expect(status(consent: consent, enabled: false, ack: recent) == .paused)
        #expect(status(consent: consent, ends: t0.addingTimeInterval(-1), ack: recent) == .ended)
        #expect(status(consent: consent, ack: nil) == .noRecentSignal)          // never acknowledged: not "active"
        #expect(status(consent: consent, ack: old) == .noRecentSignal)          // stale ack: not "active" (AT-42)
        #expect(status(consent: consent, auth: .whenInUse, ack: recent) == .sharing)
        #expect(status(consent: consent, auth: .always, ack: recent) == .sharing)
    }

    @Test func withheldConsentBlocksEverythingElse() {
        // AT-41: no consent means "Not tracking" whatever the OS permission or past uploads say.
        for auth in [OSLocationAuth.always, .whenInUse, .denied, .notDetermined] {
            #expect(status(consent: nil, auth: auth, ack: t0) == .needsConsent)
        }
    }

    @Test func ageTextNeverRoundsStaleIntoNow() {
        #expect(Age.text(from: nil, now: t0) == "Never")
        #expect(Age.text(from: t0.addingTimeInterval(-10), now: t0) == "Just now")
        #expect(Age.text(from: t0.addingTimeInterval(-120), now: t0) == "2 min ago")
        #expect(Age.text(from: t0.addingTimeInterval(-7200), now: t0) == "2 h ago")
        #expect(Age.text(from: t0.addingTimeInterval(-3 * 86400), now: t0) == "3 d ago")
    }

    // MARK: loopback server = the rules a real transport must honour

    func server(_ c: TestClock) -> LoopbackServer { LoopbackServer(now: { c.now }) }
    let unit = LoopbackServer.Unit(deviceID: UUID(), unitCode: "IP-001", businessName: "Papa Rental")

    @Test func claimBindsToTheIssuedUnitAndIsSingleUse() async throws {
        let s = server(TestClock(t0))
        let code = await s.issue(for: unit)
        let claim = try await s.claim(code: PairingCode.display(code).lowercased())
        #expect(claim.unitCode == "IP-001" && claim.businessName == "Papa Rental" && claim.deviceID == unit.deviceID)
        #expect(claim.credential.count == 64)
        await #expect(throws: TransportError.alreadyUsed) { try await s.claim(code: code) }            // AT-40: reuse rejected
    }

    @Test func expiredAndUnknownCodesAreRejected() async throws {
        let clock = TestClock(t0), s = server(clock)
        let code = await s.issue(for: unit)
        clock.advance(PairingCode.lifetime + 1)
        await #expect(throws: TransportError.expired) { try await s.claim(code: code) }                // AT-40: expiry
        await #expect(throws: TransportError.invalidCode) { try await s.claim(code: "ABCD-EFGH") }
        await #expect(throws: TransportError.invalidCode) { try await s.claim(code: "nope") }
    }

    @Test func codeLivesExactlyOneMinute() async throws {
        #expect(PairingCode.lifetime == 60)
        let early = TestClock(t0), a = server(early)
        let c1 = await a.issue(for: unit)
        early.advance(59)
        _ = try await a.claim(code: c1)                                                    // 59 s: still good
        let late = TestClock(t0), b = server(late)
        let c2 = await b.issue(for: unit)
        late.advance(61)
        await #expect(throws: TransportError.expired) { try await b.claim(code: c2) }      // 61 s: gone
    }

    @Test func differentUnitsGetDifferentCredentialsThatOnlyWriteTheirOwnUnit() async throws {
        let s = server(TestClock(t0))
        let other = LoopbackServer.Unit(deviceID: UUID(), unitCode: "IP-002", businessName: "Other Business")
        let a = try await s.claim(code: await s.issue(for: unit)), b = try await s.claim(code: await s.issue(for: other))
        #expect(a.credential != b.credential && a.deviceID != b.deviceID)
        _ = try await s.upload([sample(at: t0)], credential: a.credential)
        #expect(await s.lastLocation(deviceID: unit.deviceID) != nil)
        #expect(await s.lastLocation(deviceID: other.deviceID) == nil)       // a's credential cannot touch b's unit
    }

    @Test func uploadAcknowledgesStoresLatestAndNeverRollsBack() async throws {
        let s = server(TestClock(t0))
        let claim = try await s.claim(code: await s.issue(for: unit))
        let newer = sample(-8.7, 115.3, at: t0), older = sample(-8.6, 115.1, at: t0.addingTimeInterval(-600))
        let acked = try await s.upload([newer, older], credential: claim.credential)
        #expect(Set(acked) == [newer.id, older.id])
        #expect(await s.lastLocation(deviceID: unit.deviceID)?.id == newer.id)      // AT-18: out-of-order point does not win
        let again = try await s.upload([newer], credential: claim.credential)       // duplicate retry: acked, not applied twice
        #expect(again == [newer.id])
    }

    @Test func invalidSamplesAreAckedSoTheyAreNotRetriedButNeverStored() async throws {
        let s = server(TestClock(t0))
        let claim = try await s.claim(code: await s.issue(for: unit))
        let bad = sample(95, 0, at: t0)
        let acked = try await s.upload([bad], credential: claim.credential)
        let stored = await s.lastLocation(deviceID: unit.deviceID)
        #expect(acked == [bad.id] && stored == nil)
    }

    @Test func revokedOrUnknownCredentialsAreRejected() async throws {
        let s = server(TestClock(t0))
        let claim = try await s.claim(code: await s.issue(for: unit))
        _ = try await s.upload([sample(at: t0)], credential: claim.credential)
        try await s.revoke(credential: claim.credential)
        await #expect(throws: TransportError.unauthorized) { try await s.upload([sample(at: t0.addingTimeInterval(5))], credential: claim.credential) }   // AT-17, AT-44
        await #expect(throws: TransportError.unauthorized) { try await s.upload([sample()], credential: "forged") }
        await #expect(throws: TransportError.unauthorized) { try await s.revoke(credential: "forged") }
    }

    @Test func unconfiguredTransportFailsHonestly() async {
        let t = UnconfiguredTransport()
        await #expect(throws: TransportError.notConfigured) { try await t.claim(code: "K7M2-9QXA", installationID: UUID()) }
        await #expect(throws: TransportError.notConfigured) { try await t.upload([], credential: "x") }
    }
}

// MARK: owner-side reading rules (CloudKit has no server code, so the admin app enforces these)

struct LocationAggregatorTests {
    let t0 = Date(timeIntervalSince1970: 1_792_900_000)
    let dev = UUID(), inst = UUID()
    func inbound(_ lat: Double = -8.65, at: Date? = nil, id: UUID = UUID(), installation: UUID? = nil, acc: Double = 10) -> InboundSample {
        InboundSample(deviceID: dev, installationID: installation ?? inst,
                      sample: LocationSample(id: id, latitude: lat, longitude: 115.2, horizontalAccuracyM: acc, measuredAt: at ?? t0), receivedAt: t0)
    }

    @Test func revokedInstallationsAreIgnored() {
        let revokedID = UUID()
        let kept = LocationAggregator.accept([inbound(installation: revokedID), inbound()], revoked: [revokedID], knownSampleIDs: [], now: t0)
        #expect(kept.count == 1 && kept[0].installationID == inst)                      // AT-44: late writes from a revoked phone never count
    }

    @Test func invalidDuplicateAndAlreadyStoredPointsAreDropped() {
        let dup = UUID(), stored = UUID()
        let kept = LocationAggregator.accept([inbound(95), inbound(acc: 9000), inbound(at: t0.addingTimeInterval(3600)),
                                              inbound(id: dup), inbound(id: dup), inbound(id: stored), inbound()],
                                             revoked: [], knownSampleIDs: [stored], now: t0)
        #expect(kept.count == 2 && kept.filter { $0.sample.id == dup }.count == 1)
    }

    @Test func pointsPastRetentionAreDropped() {
        let old = inbound(at: t0.addingTimeInterval(-(LocationAggregator.retention + 1))), edge = inbound(at: t0.addingTimeInterval(-LocationAggregator.retention))
        #expect(LocationAggregator.accept([old, edge], revoked: [], knownSampleIDs: [], now: t0) == [edge])
        #expect(LocationAggregator.retention == 7 * 86_400)
    }

    @Test func outOfOrderPointsAreKeptSortedSoLatestIsNeverRolledBack() {
        let newer = inbound(-8.7, at: t0), older = inbound(-8.6, at: t0.addingTimeInterval(-600))
        let kept = LocationAggregator.accept([newer, older], revoked: [], knownSampleIDs: [], now: t0)
        #expect(kept.map(\.sample.id) == [older.sample.id, newer.sample.id] && kept.last == newer)   // AT-18
    }

    @Test func loopbackOwnerRoundTripFeedsTheReader() async throws {
        let clock = TestClock(t0)
        let server = LoopbackServer(now: { clock.now }), owner = LoopbackOwner(server: server, now: { clock.now })
        let unit = PairingUnit(deviceID: dev, unitCode: "IP-001", businessName: "B", deviceModel: "iPhone 15")
        let issued = try await owner.issuePairing(for: unit)
        #expect(issued.expiresAt == t0.addingTimeInterval(60))
        let claim = try await LoopbackTransport(server: server).claim(code: issued.code, installationID: inst)
        _ = try await server.upload([LocationSample(latitude: -8.65, longitude: 115.2, horizontalAccuracyM: 10, measuredAt: t0)], credential: claim.credential)
        var batch = try await owner.inbound()
        #expect(batch.samples.count == 1 && batch.samples[0].installationID == inst && batch.samples[0].deviceID == dev)
        #expect(LocationAggregator.accept(batch.samples, revoked: batch.revokedInstallations, knownSampleIDs: [], now: t0).count == 1)
        try await owner.revoke(deviceID: dev)
        batch = try await owner.inbound()
        #expect(batch.revokedInstallations == [inst])
        #expect(LocationAggregator.accept(batch.samples, revoked: batch.revokedInstallations, knownSampleIDs: [], now: t0).isEmpty)
        await #expect(throws: TransportError.unauthorized) { try await server.upload([], credential: claim.credential) }
    }

    @Test func unconfiguredGatewayFailsHonestly() async {
        let g = UnconfiguredOwnerGateway()
        await #expect(throws: TransportError.notConfigured) { try await g.inbound() }
        await #expect(throws: TransportError.notConfigured) { try await g.issuePairing(for: PairingUnit(deviceID: UUID(), unitCode: "x", businessName: "b", deviceModel: "m")) }
    }
}

// MARK: CloudKit record mapping (offline: CKRecord needs no account). The network calls themselves are unverified.

struct CloudKitSchemaTests {
    let t0 = Date(timeIntervalSince1970: 1_792_900_000)
    let zone = CKSchema.zoneID()
    let unit = PairingUnit(deviceID: UUID(), unitCode: "IP-001", businessName: "Papa Rental", deviceModel: "iPhone 15 Pro")

    @Test func tokenIsKeyedByHashAndNeverCarriesThePlainCode() {
        let code = "K7M29QXA", r = CKSchema.tokenRecord(codeHash: PairingCode.hash(code), unit: unit, zone: zone)
        #expect(r.recordID.recordName == PairingCode.hash(code) && r.recordType == CKSchema.Kind.token)
        for k in r.allKeys() { #expect((r[k] as? String)?.contains(code) != true) }
        #expect(CKSchema.unit(from: r) == unit)
        #expect(!CKSchema.isClaimed(r))
        CKSchema.markClaimed(r, by: UUID(), at: t0)
        #expect(CKSchema.isClaimed(r))
    }

    @Test func expiryUsesServerTimestampsAndOneMinute() {
        #expect(!CKSchema.isExpired(created: t0, claimedAt: t0.addingTimeInterval(59)))
        #expect(!CKSchema.isExpired(created: t0, claimedAt: t0.addingTimeInterval(60)))
        #expect(CKSchema.isExpired(created: t0, claimedAt: t0.addingTimeInterval(61)))
        #expect(!CKSchema.isExpired(created: nil, claimedAt: t0) && !CKSchema.isExpired(created: t0, claimedAt: nil))
    }

    @Test func sampleRoundTripsAndRetriesCannotDuplicate() throws {
        let s = LocationSample(latitude: -8.65, longitude: 115.2167, horizontalAccuracyM: 18, measuredAt: t0)
        let inst = UUID()
        let r = CKSchema.sampleRecord(s, deviceID: unit.deviceID, installationID: inst, zone: zone)
        #expect(r.recordID.recordName == s.id.uuidString)                 // same id, same record: a retry overwrites nothing new
        let back = try #require(CKSchema.inbound(from: r))
        #expect(back.sample == s && back.deviceID == unit.deviceID && back.installationID == inst && back.receivedAt == t0)
    }

    @Test func malformedOrForeignRecordsAreIgnored() {
        let junk = CKRecord(recordType: CKSchema.Kind.sample, recordID: CKRecord.ID(recordName: "not-a-uuid", zoneID: zone))
        #expect(CKSchema.inbound(from: junk) == nil)
        let other = CKRecord(recordType: "Something", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        #expect(CKSchema.inbound(from: other) == nil && CKSchema.unit(from: other) == nil)
    }

    @Test func installationRevocationIsExplicit() {
        let id = UUID(), r = CKSchema.installationRecord(id: id, unit: unit, zone: zone)
        #expect(r.recordID.recordName == id.uuidString && !CKSchema.isRevoked(r))
        CKSchema.revoke(r, at: t0)
        #expect(CKSchema.isRevoked(r))
    }

    @Test func cloudKitErrorsMapToHonestTransportErrors() {
        #expect(CKSchema.transportError(CKError(.notAuthenticated)) == .noICloudAccount)
        #expect(CKSchema.transportError(CKError(.serverRecordChanged)) == .alreadyUsed)
        #expect(CKSchema.transportError(CKError(.unknownItem)) == .invalidCode)
        #expect(CKSchema.transportError(CKError(.networkUnavailable)) == .offline)
        #expect(CKSchema.transportError(CKError(.permissionFailure)) == .notConfigured)
        #expect(CKSchema.transportError(URLError(.notConnectedToInternet)) == .offline)
        #expect(TransportError.noICloudAccount.userMessage.contains("iCloud"))
    }
}

// MARK: fleet sharing state (owner and tracker views of the one-time CKShare)

struct FleetSharingTests {
    func p(owner: Bool = false, accepted: Bool = false, write: Bool = true) -> ShareParticipantInfo { .init(isOwner: owner, accepted: accepted, canWrite: write) }

    @Test func ownerStateFollowsTheSetupOrder() {
        #expect(FleetSharing.ownerState(configured: false, accountAvailable: true, participants: []) == .notConfigured)
        #expect(FleetSharing.ownerState(configured: false, accountAvailable: false, participants: [p(owner: true)]) == .notConfigured)   // no container beats everything
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: false, participants: []) == .noICloudAccount)
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: []) == .notShared)
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: [p(owner: true, accepted: true)]) == .notShared)   // only the owner: nothing shared
    }

    @Test func sharedStateCountsAcceptedAndPendingAndChecksWritePermission() {
        let owner = p(owner: true, accepted: true)
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: [owner, p()]) == .shared(accepted: 0, pending: 1, writable: false))
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: [owner, p(accepted: true)]) == .shared(accepted: 1, pending: 0, writable: true))
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: [owner, p(accepted: true, write: false)]) == .shared(accepted: 1, pending: 0, writable: false))
        #expect(FleetSharing.ownerState(configured: true, accountAvailable: true, participants: [owner, p(accepted: true), p()]) == .shared(accepted: 1, pending: 1, writable: true))
    }

    @Test func trackerAccessNeedsContainerAccountAndAVisibleZone() {
        #expect(FleetSharing.access(configured: false, accountAvailable: true, zoneVisible: true) == .notConfigured)
        #expect(FleetSharing.access(configured: true, accountAvailable: false, zoneVisible: true) == .noICloudAccount)
        #expect(FleetSharing.access(configured: true, accountAvailable: true, zoneVisible: false) == .notShared)
        #expect(FleetSharing.access(configured: true, accountAvailable: true, zoneVisible: true) == .linked)
    }

    @Test func shareIsInviteOnlyAndTitled() {
        let s = FleetSharing.configuredShare(zone: CKSchema.zoneID())
        #expect(s.publicPermission == .none)                                   // never a public link
        #expect(s[CKShare.SystemFieldKey.title] as? String == "Rentro fleet")
        #expect(FleetSharing.participants(from: s).filter { !$0.isOwner }.isEmpty)
    }
}

// MARK: colour contrast (WCAG AA 4.5:1) for every text token on the surfaces it is used on, read from the real tokens

import SwiftUI
import UIKit

struct ContrastTests {
    static func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func lum(_ c: Color, _ style: UIUserInterfaceStyle) -> Double {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * lin(Double(r)) + 0.7152 * lin(Double(g)) + 0.0722 * lin(Double(b))
    }
    static func ratio(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let (x, y) = (lum(a, style), lum(b, style)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // Text on the surface it actually sits on.
    static let pairs: [(String, Color, Color)] = [
        ("secondary/surface", .textSecondary, .bgSurface), ("secondary/canvas", .textSecondary, .bgCanvas), ("secondary/subtle", .textSecondary, .bgSubtle),
        ("primary/surface", .textPrimary, .bgSurface), ("accent/canvas", .textAccent, .bgCanvas), ("accent/surface", .textAccent, .bgSurface),
        ("success/pill", .textSuccess, .bgSuccess), ("warning/pill", .textWarning, .bgWarning), ("danger/pill", .textDanger, .bgDanger),
        ("onSoft/subtle", .textOnSoft, .bgSubtle), ("headerSecondary/brand", .textHeaderSecondary, .brandSolid), ("onBrand/brand", .textOnBrand, .brandSolid)]

    @Test func everyTextTokenPassesAAInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for (name, fg, bg) in Self.pairs {
                let r = Self.ratio(fg, bg, style)
                #expect(r >= 4.5, "\(name) in \(style == .dark ? "dark" : "light") is \(r)")
            }
        }
    }

    @Test func secondaryTextKeepsHeadroomForThinFonts() {
        // Thin caption text loses contrast when anti-aliased: keep secondary text comfortably above the 4.5:1 minimum on light surfaces.
        for bg in [Color.bgSurface, .bgCanvas, .bgSubtle] { #expect(Self.ratio(.textSecondary, bg, .light) >= 5.5) }
    }

    @Test func statusTextKeepsHeadroomOnItsPill() {
        // Semibold 17 pt text on a tinted pill (e.g. the red Unpair button) sat just above 4.5:1 and the audit flagged it.
        #expect(Self.ratio(.textDanger, .bgDanger, .light) >= 5.5)
        #expect(Self.ratio(.textWarning, .bgWarning, .light) >= 5.5)
        #expect(Self.ratio(.textSuccess, .bgSuccess, .light) >= 5.5)
    }

    @Test func theCheckerCatchesAFailingPair() {
        // Figma's original light secondary (#78908b) on white must fail: proves the test can fail.
        #expect(Self.ratio(Color(red: 0x78 / 255, green: 0x90 / 255, blue: 0x8b / 255), .bgSurface, .light) < 4.5)
    }
}

// MARK: brand intro policy (B03, AT-32, AT-33)

struct BrandIntroPolicyTests {
    @Test func playsOnlyOnFirstRunWithoutReduceMotion() {
        #expect(BrandIntroPolicy.shouldPlay(seen: false, reduceMotion: false))
        #expect(!BrandIntroPolicy.shouldPlay(seen: true, reduceMotion: false))     // returning users: never again
        #expect(!BrandIntroPolicy.shouldPlay(seen: false, reduceMotion: true))     // Reduce Motion: static content at once
        #expect(!BrandIntroPolicy.shouldPlay(seen: true, reduceMotion: true))
    }
    @Test func introIsShortAndNeverALongBlock() {
        #expect(BrandIntroPolicy.baseDuration <= .seconds(2))
    }
}
