import CloudKit
import Foundation

enum CloudKitConfig {
    /// Both targets carry this container in their entitlements. Set to nil to return to the honest "not configured" path.
    static let containerID: String? = "iCloud.com.rentro.shared"
    static let zoneName = "Fleet"
}

/// Record layout for the shared "Fleet" zone. Pure mapping, so it is unit-tested without an iCloud account.
/// UNVERIFIED against a real container: see Docs/PHASE_C_REQUIREMENTS.md.
enum CKSchema {
    enum Kind { static let token = "PairingToken", installation = "Installation", sample = "LocationSample" }

    static func zoneID(owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: CloudKitConfig.zoneName, ownerName: owner)
    }

    // PairingToken: recordName is the code's hash, so the plain code never reaches iCloud.
    static func tokenRecord(codeHash: String, unit: PairingUnit, zone: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Kind.token, recordID: CKRecord.ID(recordName: codeHash, zoneID: zone))
        r["unitID"] = unit.deviceID.uuidString
        r["unitCode"] = unit.unitCode
        r["businessName"] = unit.businessName
        r["deviceModel"] = unit.deviceModel
        return r
    }
    static func unit(from token: CKRecord) -> PairingUnit? {
        guard token.recordType == Kind.token, let id = (token["unitID"] as? String).flatMap(UUID.init(uuidString:)),
              let code = token["unitCode"] as? String, let business = token["businessName"] as? String else { return nil }
        return PairingUnit(deviceID: id, unitCode: code, businessName: business, deviceModel: token["deviceModel"] as? String ?? "")
    }
    static func isClaimed(_ token: CKRecord) -> Bool { (token["claimedBy"] as? String) != nil }
    static func markClaimed(_ token: CKRecord, by installation: UUID, at: Date) {
        token["claimedBy"] = installation.uuidString
        token["claimedAt"] = at
    }
    /// Expiry is judged with server timestamps (creation vs the claim's save), never the phone's clock.
    static func isExpired(created: Date?, claimedAt serverTime: Date?, lifetime: TimeInterval = PairingCode.lifetime) -> Bool {
        guard let created, let serverTime else { return false }
        return serverTime.timeIntervalSince(created) > lifetime
    }

    // Installation: one per paired phone; revokedAt is how a pairing ends.
    static func installationRecord(id: UUID, unit: PairingUnit, zone: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Kind.installation, recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zone))
        r["deviceID"] = unit.deviceID.uuidString
        r["unitCode"] = unit.unitCode
        return r
    }
    static func isRevoked(_ installation: CKRecord) -> Bool { installation["revokedAt"] as? Date != nil }
    static func revoke(_ installation: CKRecord, at: Date) { installation["revokedAt"] = at }

    // LocationSample: recordName is the tracker's upload id, so a retried upload cannot create a second record.
    static func sampleRecord(_ s: LocationSample, deviceID: UUID, installationID: UUID, zone: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Kind.sample, recordID: CKRecord.ID(recordName: s.id.uuidString, zoneID: zone))
        r["deviceID"] = deviceID.uuidString
        r["installationID"] = installationID.uuidString
        r["latitude"] = s.latitude
        r["longitude"] = s.longitude
        r["accuracy"] = s.horizontalAccuracyM
        r["measuredAt"] = s.measuredAt
        return r
    }
    /// `receivedAt` is iCloud's creation time, not anything the phone claims.
    static func inbound(from r: CKRecord) -> InboundSample? {
        guard r.recordType == Kind.sample, let id = UUID(uuidString: r.recordID.recordName),
              let dev = (r["deviceID"] as? String).flatMap(UUID.init(uuidString:)),
              let inst = (r["installationID"] as? String).flatMap(UUID.init(uuidString:)),
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double,
              let acc = r["accuracy"] as? Double, let at = r["measuredAt"] as? Date else { return nil }
        return InboundSample(deviceID: dev, installationID: inst,
                             sample: LocationSample(id: id, latitude: lat, longitude: lon, horizontalAccuracyM: acc, measuredAt: at),
                             receivedAt: r.creationDate ?? at)
    }

    static func transportError(_ error: Error) -> TransportError {
        print("CKERR \(error)")   // the mapped message hides the cause; the console keeps it
        guard let e = error as? CKError else { return .offline }
        switch e.code {
        case .notAuthenticated: return .noICloudAccount
        case .unknownItem: return .invalidCode
        case .serverRecordChanged: return .alreadyUsed
        case .permissionFailure, .zoneNotFound, .missingEntitlement: return .notConfigured
        default: return .offline
        }
    }
}
