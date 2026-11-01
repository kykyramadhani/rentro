#if DEBUG
import CloudKit
import Foundation

/// Device-only CloudKit probe, no UI needed. Launch with `-ckSelfTest owner` (prints a fresh code, then polls for
/// samples) or `-ckSelfTest tracker CODE` (claims the code and uploads one sample). Every step prints "CKTEST …".
enum CloudKitSelfTest {
    static func runIfRequested() {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-ckSelfTest"), a.count > i + 1, let id = CloudKitConfig.containerID else { return }
        let role = a[i + 1], code = a.count > i + 2 ? a[i + 2] : nil
        Task.detached { await run(role: role, code: code, containerID: id) }
    }

    private static func log(_ s: String) { print("CKTEST \(s)"); fflush(stdout) }

    private static func run(role: String, code: String?, containerID: String) async {
        let c = CKContainer(identifier: containerID)
        do {
            log("container \(containerID) account=\(try await c.accountStatus().rawValue) (1 = available)")
            log("user \(try await c.userRecordID().recordName)")
            for (name, db) in [("private", c.privateCloudDatabase), ("shared", c.sharedCloudDatabase)] {
                log("\(name) zones: \(try await db.allRecordZones().map { "\($0.zoneID.zoneName)@\($0.zoneID.ownerName)" })")
            }
            if role == "owner" {
                let g = CloudKitOwnerGateway(containerID: containerID)
                let issued = try await g.issuePairing(for: PairingUnit(deviceID: UUID(), unitCode: "SELFTEST", businessName: "Self test", deviceModel: "iPhone"))
                log("CODE \(issued.code) expires \(issued.expiresAt)")
                for n in 0..<36 {
                    let b = try await g.inbound()
                    log("poll \(n): \(b.samples.count) samples, revoked \(b.revokedInstallations.count)")
                    if !b.samples.isEmpty { log("OWNER RECEIVED \(b.samples.map { "\($0.sample.latitude),\($0.sample.longitude)" })"); break }
                    try await Task.sleep(for: .seconds(5))
                }
            } else {
                guard let code else { log("missing code"); return }
                let t = CloudKitTrackerTransport(containerID: containerID)
                let claim = try await t.claim(code: code, installationID: UUID())
                log("CLAIMED unit \(claim.unitCode) business \(claim.businessName)")
                let s = LocationSample(latitude: -6.2, longitude: 106.8, horizontalAccuracyM: 20, measuredAt: .now)
                log("UPLOADED acked \(try await t.upload([s], credential: claim.credential).count)/1")
            }
            log("DONE")
        } catch {
            log("FAILED \(type(of: error)) \(error)")
            if let ck = error as? CKError { log("CKError code=\(ck.code.rawValue) \(ck.localizedDescription) \(ck.userInfo)") }
        }
    }
}
#endif
