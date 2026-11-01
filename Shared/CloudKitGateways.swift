import CloudKit
import Foundation

// UNVERIFIED: written against the CloudKit async API but never run against a container (none exists yet, and the
// simulator has no iCloud account). Nothing instantiates these until `CloudKitConfig.containerID` is set.

/// Owner side: the owner's private "Fleet" zone, shared once with the fleet Apple ID (CKShare, set up on devices).
struct CloudKitOwnerGateway: OwnerGateway {
    let container: CKContainer
    private var db: CKDatabase { container.privateCloudDatabase }
    private let cursorKey: String, revokedKey: String

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
        cursorKey = "ck.cursor.\(containerID)"; revokedKey = "ck.revoked.\(containerID)"
    }

    func issuePairing(for unit: PairingUnit) async throws -> IssuedCode {
        do {
            _ = try await db.save(CKRecordZone(zoneID: CKSchema.zoneID()))               // idempotent
            let code = PairingCode.generate()
            let saved = try await db.save(CKSchema.tokenRecord(codeHash: PairingCode.hash(code), unit: unit, zone: CKSchema.zoneID()))
            return IssuedCode(code: code, expiresAt: (saved.creationDate ?? .now).addingTimeInterval(PairingCode.lifetime))
        } catch { throw CKSchema.transportError(error) }
    }

    func inbound() async throws -> InboundBatch {
        do {
            let result = try await db.recordZoneChanges(inZoneWith: CKSchema.zoneID(), since: storedCursor)
            var batch = InboundBatch(revokedInstallations: storedRevoked)
            for (_, change) in result.modificationResultsByID {
                guard case .success(let m) = change else { continue }
                if let s = CKSchema.inbound(from: m.record) { batch.samples.append(s) }
                else if m.record.recordType == CKSchema.Kind.installation, CKSchema.isRevoked(m.record),
                        let id = UUID(uuidString: m.record.recordID.recordName) { batch.revokedInstallations.insert(id) }
            }
            storedRevoked = batch.revokedInstallations
            storedCursor = result.changeToken
            return batch
        } catch { throw CKSchema.transportError(error) }
    }

    func revoke(deviceID: UUID) async throws {
        do {
            let q = CKQuery(recordType: CKSchema.Kind.installation, predicate: NSPredicate(format: "deviceID == %@", deviceID.uuidString))
            let found = try await db.records(matching: q, inZoneWith: CKSchema.zoneID())
            for case let (_, .success(r)) in found.matchResults { CKSchema.revoke(r, at: .now); _ = try await db.save(r) }
        } catch { throw CKSchema.transportError(error) }
    }

    // ponytail: a cursor and a revoked set in UserDefaults; a lost cursor just re-reads history, which dedupes by sample id.
    private var storedCursor: CKServerChangeToken? {
        get { UserDefaults.standard.data(forKey: cursorKey).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) } }
        nonmutating set {
            UserDefaults.standard.set(newValue.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }, forKey: cursorKey)
        }
    }
    private var storedRevoked: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: revokedKey) ?? []).compactMap(UUID.init(uuidString:))) }
        nonmutating set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: revokedKey) }
    }
}

/// Tracker side: the shared database of the fleet Apple ID. The credential is the installation id: CloudKit sees one
/// identity for every rental phone, so "can only write unit X" is enforced here and by the owner when reading.
struct CloudKitTrackerTransport: TrackerTransport {
    let container: CKContainer

    init(containerID: String) { container = CKContainer(identifier: containerID) }

    private func zone() async throws -> (CKDatabase, CKRecordZone.ID) {
        guard let z = try await container.fleetZone() else { throw TransportError.notConfigured }
        return z
    }

    func claim(code: String, installationID: UUID) async throws -> PairingClaim {
        guard let normalized = PairingCode.normalize(code) else { throw TransportError.invalidCode }
        do {
            let (db, zoneID) = try await zone()
            let token = try await db.record(for: CKRecord.ID(recordName: PairingCode.hash(normalized), zoneID: zoneID))
            guard !CKSchema.isClaimed(token), let unit = CKSchema.unit(from: token) else { throw TransportError.alreadyUsed }
            CKSchema.markClaimed(token, by: installationID, at: .now)
            // Only one phone can win: the save fails if anyone changed the token since we read it.
            let saved = try await db.modifyRecords(saving: [token], deleting: [], savePolicy: .ifServerRecordUnchanged).saveResults[token.recordID]!.get()
            if CKSchema.isExpired(created: saved.creationDate, claimedAt: saved.modificationDate) { throw TransportError.expired }
            _ = try await db.save(CKSchema.installationRecord(id: installationID, unit: unit, zone: zoneID))
            return PairingClaim(deviceID: unit.deviceID, unitCode: unit.unitCode, businessName: unit.businessName,
                                deviceModel: unit.deviceModel, credential: installationID.uuidString)
        } catch let e as TransportError { throw e } catch { throw CKSchema.transportError(error) }
    }

    func upload(_ batch: [LocationSample], credential: String) async throws -> [UUID] {
        guard let installationID = UUID(uuidString: credential) else { throw TransportError.unauthorized }
        do {
            let (db, zoneID) = try await zone()
            let inst = try await db.record(for: CKRecord.ID(recordName: credential, zoneID: zoneID))
            guard !CKSchema.isRevoked(inst), let deviceID = (inst["deviceID"] as? String).flatMap(UUID.init(uuidString:)) else { throw TransportError.unauthorized }
            let records = batch.map { CKSchema.sampleRecord($0, deviceID: deviceID, installationID: installationID, zone: zoneID) }
            let results = try await db.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged).saveResults
            var acked: [UUID] = []
            for s in batch {
                switch results[CKRecord.ID(recordName: s.id.uuidString, zoneID: zoneID)] {
                case .success?: acked.append(s.id)
                case .failure(let e)?: if (e as? CKError)?.code == .serverRecordChanged { acked.append(s.id) } else { throw CKSchema.transportError(e) }   // duplicate = already there
                case nil: break
                }
            }
            return acked
        } catch let e as TransportError { throw e } catch { throw CKSchema.transportError(error) }
    }

    func revoke(credential: String) async throws {
        do {
            let (db, zoneID) = try await zone()
            let inst = try await db.record(for: CKRecord.ID(recordName: credential, zoneID: zoneID))
            CKSchema.revoke(inst, at: .now)
            _ = try await db.save(inst)
        } catch let e as TransportError { throw e } catch { throw CKSchema.transportError(error) }
    }
}

extension CKContainer {
    /// The Fleet zone as a tracker sees it: shared by the owner to the fleet Apple ID, or, when tracker and owner are
    /// signed in to the SAME Apple ID (testing), the account's own private zone, which needs no CKShare.
    func fleetZone() async throws -> (CKDatabase, CKRecordZone.ID)? {
        for db in [sharedCloudDatabase, privateCloudDatabase] {
            if let z = try await db.allRecordZones().first(where: { $0.zoneID.zoneName == CloudKitConfig.zoneName }) { return (db, z.zoneID) }
        }
        return nil
    }
}
