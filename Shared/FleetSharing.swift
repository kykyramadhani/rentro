import CloudKit
import Foundation

/// What the tracker phone can truthfully say about its access to the owner's fleet zone.
enum FleetAccess: Equatable, Sendable { case notConfigured, noICloudAccount, notShared, linked }

struct ShareParticipantInfo: Equatable, Sendable {
    var isOwner: Bool
    var accepted: Bool
    var canWrite: Bool
}

/// Owner-side view of the one-time share with the fleet Apple ID.
enum FleetShareState: Equatable {
    case notConfigured, noICloudAccount, notShared
    /// `writable` is false when every accepted participant is read-only: trackers must write locations.
    case shared(accepted: Int, pending: Int, writable: Bool)
}

enum FleetSharing {
    static func ownerState(configured: Bool, accountAvailable: Bool, participants: [ShareParticipantInfo]) -> FleetShareState {
        guard configured else { return .notConfigured }
        guard accountAvailable else { return .noICloudAccount }
        let others = participants.filter { !$0.isOwner }
        guard !others.isEmpty else { return .notShared }
        let accepted = others.filter(\.accepted)
        return .shared(accepted: accepted.count, pending: others.count - accepted.count, writable: accepted.contains(where: \.canWrite))
    }

    static func access(configured: Bool, accountAvailable: Bool, zoneVisible: Bool) -> FleetAccess {
        guard configured else { return .notConfigured }
        guard accountAvailable else { return .noICloudAccount }
        return zoneVisible ? .linked : .notShared
    }

    /// Zone-wide share (iOS 15+): everything in the "Fleet" zone is shared, nothing public, invitees only.
    static func configuredShare(zone: CKRecordZone.ID) -> CKShare {
        let share = CKShare(recordZoneID: zone)
        share[CKShare.SystemFieldKey.title] = "Rentro fleet"
        share.publicPermission = .none
        return share
    }

    static func participants(from share: CKShare) -> [ShareParticipantInfo] {
        share.participants.map {
            ShareParticipantInfo(isOwner: $0.role == .owner, accepted: $0.acceptanceStatus == .accepted, canWrite: $0.permission == .readWrite)
        }
    }
}
