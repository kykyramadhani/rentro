import CloudKit
import Foundation
import Network
import Observation

/// Where the pairing credential lives. Keychain in the app, a dictionary in tests (PRD 6.2: never UserDefaults).
@MainActor struct CredentialStore {
    var read: () -> String?
    var write: (String) -> Void
    var clear: () -> Void

    static let keychain: CredentialStore = {
        let slot = KeychainSlot(service: "com.rentro.tracker.pairing", account: "credential")
        return CredentialStore(read: slot.read, write: slot.write, clear: slot.clear)
    }()
    static func memory() -> CredentialStore {
        final class Box: @unchecked Sendable { var v: String? }
        let b = Box()
        return CredentialStore(read: { b.v }, write: { b.v = $0 }, clear: { b.v = nil })
    }
}

/// Small JSON file with file protection; the queue is bounded so this stays tiny.
@MainActor struct TrackerPersistence {
    var load: () -> TrackerModel.Stored?
    var save: (TrackerModel.Stored) -> Void

    static let file: TrackerPersistence = {
        let url = URL.applicationSupportDirectory.appending(path: "tracker-state.json")
        return TrackerPersistence(
            load: { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TrackerModel.Stored.self, from: $0) } },
            save: {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode($0).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            })
    }()
    static let none = TrackerPersistence(load: { nil }, save: { _ in })
}

@MainActor @Observable
final class TrackerModel {
    struct Pairing: Codable, Equatable {
        var deviceID: UUID
        var unitCode: String
        var deviceModel: String
        var businessName: String
        var installationID: UUID
    }
    struct Stored: Codable, Equatable {
        var pairing: Pairing?
        var consent: Consent?
        var sharingEnabled = true
        var sharingEndsAt: Date?
        var queue = UploadQueue()
        var lastFixAt: Date?
        var lastUploadAckAt: Date?
        var lastUploadError: String?
        var uploadAttempt = 0
    }

    private(set) var stored: Stored { didSet { persistence.save(stored) } }
    private(set) var auth: OSLocationAuth
    private(set) var busy = false
    private(set) var pairError: String?
    private(set) var notice: String?
    private(set) var isOnline = true
    /// nil until checked; pairing is only offered while it is nil or `.linked`.
    private(set) var fleetAccess: FleetAccess?
    var consentDeferred = false

    private let transport: TrackerTransport
    private let location: LocationProviding
    private let credentials: CredentialStore
    private let fleet: FleetLinking
    private let persistence: TrackerPersistence
    private let policy = SamplingPolicy()
    private let now: () -> Date
    private let scheduleRetry: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private var lastRecorded: LocationSample?
    private var flushing = false
    private var monitor: NWPathMonitor?

    init(transport: TrackerTransport, location: LocationProviding, credentials: CredentialStore, fleet: FleetLinking = NoFleetLink(),
         persistence: TrackerPersistence = .none,
         now: @escaping () -> Date = { .now },
         scheduleRetry: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
             Task { @MainActor in try? await Task.sleep(for: .seconds(delay)); work() }
         }) {
        self.transport = transport
        self.location = location
        self.credentials = credentials
        self.fleet = fleet
        self.persistence = persistence
        self.now = now
        self.scheduleRetry = scheduleRetry
        var s = persistence.load() ?? Stored()
        if credentials.read() == nil { s = Stored() }           // a pairing without its credential is not a pairing
        stored = s
        auth = location.authorization
        location.onAuthChange = { [weak self] in self?.authChanged($0) }
        location.onSample = { [weak self] in self?.ingest($0) }
        applyCollection()
    }

    /// Connectivity for diagnostics only; it never gates anything.
    func watchNetwork() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.isOnline = path.status == .satisfied } }
        m.start(queue: .global(qos: .utility))
        monitor = m
    }

    var canAttemptPairing: Bool { fleetAccess == nil || fleetAccess == .linked }
    /// Why pairing is unavailable, in words the renter can act on.
    var fleetMessage: String? {
        switch fleetAccess {
        case .notConfigured?: String(localized: "Pairing isn't available in this build yet.")
        case .noICloudAccount?: String(localized: "Sign in to iCloud in Settings with the fleet Apple ID.")
        case .notShared?: String(localized: "Waiting for the owner to share the fleet with this Apple ID.")
        case .linked?, nil: nil
        }
    }
    func refreshFleetAccess() async { fleetAccess = await fleet.access() }
    /// Tapping the owner's share link lands here (CKShare acceptance). UNVERIFIED on device.
    func acceptFleetShare(_ metadata: CKShare.Metadata) async {
        do { try await fleet.accept(metadata) } catch let e as TransportError { pairError = e.userMessage } catch { pairError = TransportError.offline.userMessage }
        await refreshFleetAccess()
    }

    var pairing: Pairing? { stored.pairing }
    var isPrecise: Bool { location.isPrecise }
    var queuedCount: Int { stored.queue.samples.count }
    var needsConsentScreen: Bool { stored.pairing != nil && stored.consent?.isActive != true && !consentDeferred }

    var status: TrackerStatus {
        TrackerStatus.derive(paired: stored.pairing != nil, consent: stored.consent, auth: auth, sharingEnabled: stored.sharingEnabled,
                             sharingEndsAt: stored.sharingEndsAt, lastUploadAckAt: stored.lastUploadAckAt, now: now())
    }

    /// Coordinates are collected only with active consent, an OS grant, and sharing switched on (PRD T02, AT-41).
    private var canCollect: Bool {
        guard stored.pairing != nil, stored.consent?.isActive == true, stored.sharingEnabled else { return false }
        if let end = stored.sharingEndsAt, now() >= end { return false }
        return auth == .whenInUse || auth == .always
    }

    // MARK: T01 pairing

    func pair(code: String) async {
        guard !busy else { return }
        guard let normalized = PairingCode.fromQR(code) else { pairError = Self.message(.invalidCode); return }
        busy = true; pairError = nil; notice = nil
        defer { busy = false }
        let installation = UUID()
        do {
            let claim = try await transport.claim(code: normalized, installationID: installation)
            credentials.write(claim.credential)
            stored = Stored(pairing: Pairing(deviceID: claim.deviceID, unitCode: claim.unitCode, deviceModel: claim.deviceModel,
                                             businessName: claim.businessName, installationID: installation))
            consentDeferred = false
            lastRecorded = nil
        } catch let e as TransportError {
            pairError = Self.message(e)
        } catch { pairError = Self.message(.offline) }
    }

    // MARK: T02 consent and OS permission

    func acceptConsent() {
        guard let p = stored.pairing else { return }
        stored.consent = Consent(version: ConsentText.version, acceptedAt: now(), revokedAt: nil, businessName: p.businessName, unitCode: p.unitCode)
        consentDeferred = false
        auth = location.authorization
        if auth == .notDetermined { location.requestWhenInUse() }   // only after the explanation, and only once
        applyCollection()
    }
    func declineConsent() { consentDeferred = true }

    // MARK: T03 controls

    func setSharing(_ on: Bool) { stored.sharingEnabled = on; applyCollection() }
    func requestBackgroundSharing() { guard auth == .whenInUse else { return }; location.requestAlways() }

    private func authChanged(_ a: OSLocationAuth) { auth = a; applyCollection() }
    private func applyCollection() {
        if canCollect { location.start(background: auth == .always) } else { location.stop() }
    }

    // MARK: sampling and upload

    func ingest(_ s: LocationSample, forced: Bool = false) {
        guard canCollect else { return }
        stored.lastFixAt = s.measuredAt
        guard SampleValidator.check(s, now: now()) == .valid else { return }
        guard forced || policy.shouldRecord(previous: lastRecorded, candidate: s) else { return }
        lastRecorded = s
        stored.queue.enqueue(s, now: now())
        Task { await flush() }
    }

    func flush() async {
        guard canCollect, !flushing, let credential = credentials.read(), !stored.queue.samples.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        while canCollect, !stored.queue.samples.isEmpty {
            do {
                let acked = try await transport.upload(stored.queue.nextBatch(), credential: credential)
                stored.queue.acknowledge(acked)
                stored.lastUploadAckAt = now()
                stored.lastUploadError = nil
                stored.uploadAttempt = 0
            } catch TransportError.unauthorized {
                endedByBusiness(); return
            } catch let e as TransportError {
                failUpload(Self.message(e)); return
            } catch { failUpload(Self.message(.offline)); return }
        }
    }

    private func failUpload(_ text: String) {
        stored.lastUploadError = text
        stored.uploadAttempt += 1
        scheduleRetry(Backoff.delay(attempt: stored.uploadAttempt - 1)) { [weak self] in Task { await self?.flush() } }
    }

    /// The business revoked this pairing: stop at once and forget everything that could be sent.
    private func endedByBusiness() {
        location.stop()
        credentials.clear()
        stored = Stored()
        lastRecorded = nil
        notice = String(localized: "The rental business ended this pairing. Location sharing has stopped.")
    }

    /// T04: user-initiated, only after permission, and it shows up as a real measurement and a real upload.
    func sendTestLocation() {
        guard canCollect else { return }
        location.requestOneShot()
    }
    func ingestUserInitiated(_ s: LocationSample) { ingest(s, forced: true) }

    // MARK: T05 unpair

    func unpair() async {
        let credential = credentials.read()
        location.stop()
        var revokeFailed = false
        if let credential {
            do { try await transport.revoke(credential: credential) } catch { revokeFailed = true }
        }
        credentials.clear()
        stored = Stored()                       // wipes pairing, consent and every queued coordinate
        lastRecorded = nil
        consentDeferred = false
        notice = revokeFailed ? String(localized: "Unpaired on this iPhone. Couldn't reach the business to confirm; they can also revoke it on their side.") : nil
    }

    func dismissNotice() { notice = nil }

    static func message(_ e: TransportError) -> String { e.userMessage }
}
