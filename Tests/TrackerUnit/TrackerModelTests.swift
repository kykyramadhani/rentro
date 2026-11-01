import CloudKit
import Foundation
import Testing
@testable import RentroTracker

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    init(_ t: Date) { self.t = t }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

/// Wraps the loopback server so a test can pull the network away.
final class Flaky: TrackerTransport, @unchecked Sendable {
    let inner: LoopbackTransport
    var offline = false
    var revokeFails = false
    init(_ server: LoopbackServer) { inner = LoopbackTransport(server: server) }
    func claim(code: String, installationID: UUID) async throws -> PairingClaim { try await inner.claim(code: code, installationID: installationID) }
    func upload(_ batch: [LocationSample], credential: String) async throws -> [UUID] {
        if offline { throw TransportError.offline }
        return try await inner.upload(batch, credential: credential)
    }
    func revoke(credential: String) async throws {
        if revokeFails { throw TransportError.offline }
        try await inner.revoke(credential: credential)
    }
}

final class Retries: @unchecked Sendable { var delays: [TimeInterval] = []; var pending: [@MainActor () -> Void] = [] }

@MainActor
struct Rig {
    let clock = Clock(Date(timeIntervalSince1970: 1_792_900_000))
    let server: LoopbackServer
    let transport: Flaky
    let location = FakeLocationProvider()
    let retries = Retries()
    let credentialBox = CredentialBox()
    var model: TrackerModel
    let unit = LoopbackServer.Unit(deviceID: UUID(), unitCode: "IP-001", businessName: "Papa Rental", deviceModel: "iPhone 15 Pro")

    final class CredentialBox: @unchecked Sendable { var value: String? }

    init(persistence: TrackerPersistence = .none) {
        let clock = self.clock
        server = LoopbackServer(now: { clock.now })
        transport = Flaky(server)
        let box = credentialBox, retries = self.retries
        model = TrackerModel(transport: transport, location: location,
                             credentials: CredentialStore(read: { box.value }, write: { box.value = $0 }, clear: { box.value = nil }),
                             persistence: persistence, now: { clock.now },
                             scheduleRetry: { delay, work in retries.delays.append(delay); retries.pending.append(work) })
    }

    func code() async -> String { await server.issue(for: unit) }
    func pairAndConsent(auth: OSLocationAuth = .whenInUse) async {
        location.grantOnRequest = auth
        await model.pair(code: await code())
        model.acceptConsent()
    }
    func fix(_ lat: Double = -8.65, _ lon: Double = 115.2, after s: TimeInterval = 0) -> LocationSample {
        LocationSample(latitude: lat, longitude: lon, horizontalAccuracyM: 10, measuredAt: clock.now.addingTimeInterval(s))
    }
}

@MainActor
func eventually(_ cond: @autoclosure () -> Bool) async {
    for _ in 0..<200 where !cond() { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
}

@MainActor
struct TrackerModelTests {
    // MARK: pairing (T01)

    @Test func pairingStoresTheUnitButCollectsNothing() async {
        let r = Rig()
        await r.model.pair(code: await r.code())
        #expect(r.model.pairing?.unitCode == "IP-001" && r.model.pairing?.businessName == "Papa Rental")
        #expect(r.credentialBox.value?.count == 64)
        #expect(r.model.status == .needsConsent && r.model.needsConsentScreen)
        r.location.emit(r.fix())                                   // a stray fix before consent must go nowhere (AT-41)
        #expect(r.model.queuedCount == 0 && r.model.stored.lastFixAt == nil && !r.location.started)
    }

    @Test func badExpiredAndReusedCodesAreRefusedWithClearCopy() async {
        let r = Rig()
        await r.model.pair(code: "nope")
        #expect(r.model.pairError == TrackerModel.message(.invalidCode) && r.model.pairing == nil)
        let code = await r.code()
        r.clock.advance(PairingCode.lifetime + 1)
        await r.model.pair(code: code)
        #expect(r.model.pairError == TrackerModel.message(.expired) && r.model.pairing == nil)       // AT-40
        let fresh = await r.code()
        await r.model.pair(code: fresh)
        #expect(r.model.pairing != nil)
        await r.model.unpair()
        await r.model.pair(code: fresh)
        #expect(r.model.pairError == TrackerModel.message(.alreadyUsed) && r.model.pairing == nil)   // re-pairing needs a fresh code
    }

    @Test func qrPayloadAndManualFormsBothPair() async {
        let r = Rig()
        await r.model.pair(code: PairingCode.qrPayload(await r.code()))
        #expect(r.model.pairing != nil)
    }

    // MARK: consent and permission (T02, AT-41)

    @Test func consentThenPermissionStartsLocationOnlyWhenBothHold() async {
        let r = Rig()
        await r.model.pair(code: await r.code())
        #expect(!r.location.started)
        r.model.acceptConsent()
        #expect(r.location.requests == ["whenInUse"])               // OS prompt only after the explanation
        #expect(r.model.stored.consent?.version == ConsentText.version && r.model.stored.consent?.isActive == true)
        #expect(r.location.started && !r.location.startedInBackground)   // When In Use first, no background without "Always"
    }

    @Test func decliningConsentKeepsTheDeviceNotTracking() async {
        let r = Rig()
        await r.model.pair(code: await r.code())
        r.model.declineConsent()
        #expect(r.model.status == .needsConsent && !r.model.needsConsentScreen)
        #expect(r.location.requests.isEmpty && !r.location.started)       // the OS prompt is never shown without consent
    }

    @Test func deniedPermissionMeansPermissionRequiredAndNoCollection() async {
        let r = Rig()
        await r.pairAndConsent(auth: .denied)
        #expect(r.model.status == .permissionRequired && !r.location.started)
        r.location.emit(r.fix())
        #expect(r.model.queuedCount == 0)
    }

    @Test func revokingPermissionInSettingsStopsCollectionAtOnce() async {
        let r = Rig()
        await r.pairAndConsent()
        #expect(r.location.started)
        r.location.setAuth(.denied)                                   // AT-17: renter turns it off in iOS Settings
        #expect(!r.location.started && r.model.status == .permissionRequired)
        r.location.emit(r.fix(after: 60))
        #expect(r.model.queuedCount == 0)
    }

    @Test func alwaysIsOfferedOnlyAfterWhenInUseAndStartsBackgroundDelivery() async {
        let r = Rig()
        await r.model.pair(code: await r.code())
        r.model.requestBackgroundSharing()                            // no consent/permission yet: nothing happens
        #expect(r.location.requests.isEmpty)
        r.model.acceptConsent()
        r.model.requestBackgroundSharing()
        #expect(r.location.requests == ["whenInUse", "always"] && r.location.startedInBackground && r.model.auth == .always)
    }

    // MARK: upload (AT-15, AT-16, AT-42, AT-43)

    @Test func acknowledgedUploadMakesTheDeviceTrulyActive() async {
        let r = Rig()
        await r.pairAndConsent()
        #expect(r.model.status == .noRecentSignal)                   // consent + permission alone are not "active"
        let s = r.fix()
        r.location.emit(s)
        await eventually(r.model.status == .sharing)
        #expect(r.model.status == .sharing && r.model.queuedCount == 0)
        #expect(await r.server.lastLocation(deviceID: r.unit.deviceID)?.id == s.id)      // AT-15
        r.clock.advance(31 * 60)
        #expect(r.model.status == .noRecentSignal)                   // AT-42: a stale ack is not "active"
    }

    @Test func failedUploadKeepsThePointsSurfacesTheErrorAndRetriesWithBackoff() async {
        let r = Rig()
        await r.pairAndConsent()
        r.transport.offline = true
        r.location.emit(r.fix())
        await eventually(r.model.stored.lastUploadError != nil)
        #expect(r.model.queuedCount == 1 && r.model.stored.lastUploadError == TrackerModel.message(.offline))
        #expect(r.model.stored.lastFixAt != nil && r.model.stored.lastUploadAckAt == nil)   // AT-43: measurement fine, upload failed
        #expect(r.retries.delays == [5])
        r.transport.offline = false
        await r.model.flush()
        #expect(r.model.queuedCount == 0 && r.model.stored.lastUploadError == nil && r.model.status == .sharing)
    }

    @Test func repeatedFailuresBackOffExponentially() async {
        let r = Rig()
        await r.pairAndConsent()
        r.transport.offline = true
        r.location.emit(r.fix())
        await eventually(!r.retries.delays.isEmpty)
        await r.model.flush(); await r.model.flush()
        #expect(r.retries.delays == [5, 10, 20])
    }

    @Test func tinyMovementsAreNotRecordedButUserInitiatedTestsAre() async {
        let r = Rig()
        await r.pairAndConsent()
        r.location.emit(r.fix(-8.65, 115.2, after: 0))
        await eventually(r.model.queuedCount == 0 && r.model.stored.lastUploadAckAt != nil)
        r.location.emit(r.fix(-8.65, 115.2, after: 20))               // same spot 20 s later: dropped by the sampling policy
        #expect(r.model.queuedCount == 0 && r.model.stored.lastFixAt == r.clock.now.addingTimeInterval(20))
        r.transport.offline = true
        r.model.ingestUserInitiated(r.fix(-8.65, 115.2, after: 25))   // forced even when still: the user asked for a test
        await eventually(r.model.queuedCount == 1)
        #expect(r.model.queuedCount == 1)
    }

    @Test func invalidFixesNeverEnterTheQueue() async {
        let r = Rig()
        await r.pairAndConsent()
        r.location.emit(LocationSample(latitude: 123, longitude: 0, horizontalAccuracyM: 5, measuredAt: r.clock.now))
        r.location.emit(LocationSample(latitude: 0, longitude: 0, horizontalAccuracyM: 9000, measuredAt: r.clock.now))
        #expect(r.model.queuedCount == 0)
    }

    // MARK: pause and end

    @Test func pausingStopsCollectionAndResumingRestartsIt() async {
        let r = Rig()
        await r.pairAndConsent()
        r.model.setSharing(false)
        #expect(r.model.status == .paused && !r.location.started)
        r.location.emit(r.fix())
        #expect(r.model.queuedCount == 0)
        r.model.setSharing(true)
        #expect(r.location.started)
    }

    // MARK: business revokes (AT-17, AT-44)

    @Test func whenTheBusinessRevokesTheNextUploadWipesEverything() async {
        let r = Rig()
        await r.pairAndConsent()
        try? await r.server.revoke(credential: r.credentialBox.value!)
        r.location.emit(r.fix())
        await eventually(r.model.pairing == nil)
        #expect(r.model.pairing == nil && r.model.status == .notPaired && r.credentialBox.value == nil)
        #expect(r.model.queuedCount == 0 && !r.location.started && r.model.notice != nil)
    }

    // MARK: unpair (T05)

    @Test func unpairRevokesServerSideWipesLocalDataAndRejectsReplay() async {
        let r = Rig()
        await r.pairAndConsent()
        r.transport.offline = true
        r.location.emit(r.fix())
        await eventually(r.model.queuedCount == 1)
        let oldCredential = r.credentialBox.value!
        await r.model.unpair()
        #expect(r.model.pairing == nil && r.model.stored == TrackerModel.Stored() && r.credentialBox.value == nil && !r.location.started)
        await #expect(throws: TransportError.unauthorized) { try await r.server.upload([r.fix()], credential: oldCredential) }   // AT-44 replay rejected
        #expect(r.model.notice == nil)
    }

    @Test func unpairWorksOfflineAndSaysItCouldNotReachTheBusiness() async {
        let r = Rig()
        await r.pairAndConsent()
        r.transport.revokeFails = true
        await r.model.unpair()
        #expect(r.model.pairing == nil && r.credentialBox.value == nil)
        #expect(r.model.notice?.contains("Couldn't reach the business") == true)
    }

    // MARK: persistence

    @Test func stateSurvivesRelaunchButNotWithoutItsCredential() async {
        final class Disk: @unchecked Sendable { var data: TrackerModel.Stored? }
        let disk = Disk()
        let persistence = TrackerPersistence(load: { disk.data }, save: { disk.data = $0 })
        let r = Rig(persistence: persistence)
        await r.pairAndConsent()
        #expect(disk.data?.pairing?.unitCode == "IP-001" && disk.data?.consent?.isActive == true)

        let box = r.credentialBox
        let again = TrackerModel(transport: r.transport, location: FakeLocationProvider(authorization: .whenInUse),
                                 credentials: CredentialStore(read: { box.value }, write: { box.value = $0 }, clear: { box.value = nil }),
                                 persistence: persistence, now: { r.clock.now })
        #expect(again.pairing?.unitCode == "IP-001" && again.stored.consent?.isActive == true)

        box.value = nil                                               // Keychain wiped but the file survived: not a pairing
        let orphan = TrackerModel(transport: r.transport, location: FakeLocationProvider(), credentials: CredentialStore(read: { box.value }, write: { _ in }, clear: {}),
                                  persistence: persistence, now: { r.clock.now })
        #expect(orphan.pairing == nil && orphan.status == .notPaired)
    }

    @Test func unconfiguredBuildsFailHonestlyOnPairing() async {
        let model = TrackerModel(transport: UnconfiguredTransport(), location: FakeLocationProvider(), credentials: .memory())
        await model.pair(code: "K7M2-9QXA")
        #expect(model.pairError == TrackerModel.message(.notConfigured) && model.pairing == nil)
    }

    // MARK: fleet access (pairing is only offered when the owner's zone is actually reachable)

    func model(_ link: FleetLinking) -> TrackerModel {
        TrackerModel(transport: UnconfiguredTransport(), location: FakeLocationProvider(), credentials: .memory(), fleet: link)
    }

    @Test func pairingIsOfferedUntilProvenUnavailable() async {
        let m = model(FakeFleetLink(value: .linked))
        #expect(m.fleetAccess == nil && m.canAttemptPairing && m.fleetMessage == nil)       // not checked yet: no false alarm
        await m.refreshFleetAccess()
        #expect(m.fleetAccess == .linked && m.canAttemptPairing && m.fleetMessage == nil)
    }

    @Test func eachMissingPieceHasItsOwnHonestMessage() async {
        let none = model(NoFleetLink()); await none.refreshFleetAccess()
        #expect(!none.canAttemptPairing && none.fleetMessage == "Pairing isn't available in this build yet.")
        let noAccount = model(FakeFleetLink(value: .noICloudAccount)); await noAccount.refreshFleetAccess()
        #expect(!noAccount.canAttemptPairing && noAccount.fleetMessage?.contains("fleet Apple ID") == true)
        let unshared = model(FakeFleetLink(value: .notShared)); await unshared.refreshFleetAccess()
        #expect(!unshared.canAttemptPairing && unshared.fleetMessage?.contains("owner to share") == true)
    }

    @Test func accessRecoversWhenTheShareArrives() async {
        final class Box: @unchecked Sendable { var v = FleetAccess.notShared }
        @MainActor struct Link: FleetLinking {
            let box: Box
            func access() async -> FleetAccess { box.v }
            func accept(_ metadata: CKShare.Metadata) async throws {}
        }
        let box = Box(), m = model(Link(box: box))
        await m.refreshFleetAccess()
        #expect(!m.canAttemptPairing)
        box.v = .linked                                   // owner shared, the phone accepted the link
        await m.refreshFleetAccess()
        #expect(m.canAttemptPairing && m.fleetMessage == nil)
    }
}
