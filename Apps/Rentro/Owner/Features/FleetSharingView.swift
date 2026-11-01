import CloudKit
import Observation
import SwiftUI
import UIKit

// UNVERIFIED against iCloud: the CloudKit calls and UICloudSharingController below have never run (no container yet).
// What is tested: the state logic (`FleetSharing`) and that an unconfigured build shows the honest state and no share button.

/// The one-time share of the owner's "Fleet" zone with the fleet Apple ID (decision: one Apple ID on every rental iPhone).
@MainActor @Observable
final class FleetSharingController {
    /// nil while checking; `.notConfigured` is known immediately.
    private(set) var state: FleetShareState?
    private(set) var error: String?
    private(set) var preparing = false
    let container: CKContainer?

    init(containerID: String? = CloudKitConfig.containerID) {
        container = containerID.map { CKContainer(identifier: $0) }
        state = containerID == nil ? .notConfigured : nil
    }

    var summary: String {
        switch state {
        case nil: String(localized: "Checking…")
        case .notConfigured?: String(localized: "Not set up")
        case .noICloudAccount?: String(localized: "Sign in to iCloud")
        case .notShared?: String(localized: "Not shared")
        case .shared(let a, let p, _)?: a > 0 ? String(localized: "Shared") : String(localized: "\(p) pending")
        }
    }

    func refresh() async {
        guard let container else { state = .notConfigured; return }
        do {
            guard try await container.accountStatus() == .available else {
                state = FleetSharing.ownerState(configured: true, accountAvailable: false, participants: []); return
            }
            let share = try? await existingShare(container)           // unknownItem: nothing shared yet
            state = FleetSharing.ownerState(configured: true, accountAvailable: true, participants: share.map(FleetSharing.participants) ?? [])
            error = nil
        } catch { self.error = CKSchema.transportError(error).userMessage }
    }

    /// Creates the zone and its zone-wide share on first use, otherwise returns the existing one.
    func prepareShare() async -> CKShare? {
        guard let container else { return nil }
        preparing = true; defer { preparing = false }
        do {
            let db = container.privateCloudDatabase
            _ = try await db.save(CKRecordZone(zoneID: CKSchema.zoneID()))
            if let existing = try? await existingShare(container) { return existing }
            let draft = FleetSharing.configuredShare(zone: CKSchema.zoneID())
            return try await db.modifyRecords(saving: [draft], deleting: []).saveResults[draft.recordID]!.get() as? CKShare
        } catch { self.error = CKSchema.transportError(error).userMessage; return nil }
    }

    private func existingShare(_ container: CKContainer) async throws -> CKShare? {
        try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: CKSchema.zoneID())) as? CKShare
    }
}

/// Settings → Management → Tracker Sync.
struct FleetSharingView: View {
    @Environment(FleetSharingController.self) private var fleet
    @State private var payload: SharePayload?

    struct SharePayload: Identifiable { let id = UUID(); let share: CKShare; let container: CKContainer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                statusCard
                if let e = fleet.error { Text(e).font(.footnote).foregroundStyle(Color.textDanger).accessibilityIdentifier("rentro.fleet.error") }
                action
                Text("Use a dedicated Apple ID for the rental iPhones, never your personal one: whatever that account syncs (Photos, Messages, passwords) is visible to every renter. Turn off every iCloud sync except what Rentro Tracker needs, and wipe each phone between rentals.")
                    .font(.footnote).foregroundStyle(Color.textSecondary).accessibilityIdentifier("rentro.fleet.warning")
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Tracker Sync").navigationBarTitleDisplayMode(.inline)
        .task { await fleet.refresh() }
        .sheet(item: $payload, onDismiss: { Task { await fleet.refresh() } }) { p in
            CloudSharingView(share: p.share, container: p.container).ignoresSafeArea()
        }
    }

    @ViewBuilder private var statusCard: some View {
        let (symbol, title, body) = copy
        VStack(alignment: .leading, spacing: Space.s8) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Color.textPrimary)
            Text(body).font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .card().accessibilityElement(children: .combine).accessibilityIdentifier("rentro.fleet.status")
    }

    @ViewBuilder private var action: some View {
        switch fleet.state {
        case .notShared?, .shared?:
            Button {
                Task { if let s = await fleet.prepareShare(), let c = fleet.container { payload = SharePayload(share: s, container: c) } }
            } label: { Text(isShared ? "Manage sharing" : "Share with fleet Apple ID") }
                .buttonStyle(PrimaryButtonStyle()).disabled(fleet.preparing).accessibilityIdentifier("rentro.fleet.share")
        default: EmptyView()      // no container / no account: nothing to press, and no dead button
        }
    }

    private var isShared: Bool { if case .shared? = fleet.state { true } else { false } }

    private var copy: (String, String, String) {
        switch fleet.state {
        case nil: ("icloud", String(localized: "Checking iCloud…"), String(localized: "One moment."))
        case .notConfigured?: ("icloud.slash", String(localized: "iCloud isn't set up in this build"), String(localized: "This build isn't connected to iCloud yet, so rental iPhones can't pair. Nothing is shared."))
        case .noICloudAccount?: ("person.crop.circle.badge.exclamationmark", String(localized: "Sign in to iCloud"), String(localized: "Sign in to iCloud on this iPhone with your owner Apple ID, then come back to share the fleet."))
        case .notShared?: ("person.2.slash", String(localized: "Not shared yet"), String(localized: "Share the fleet once with the Apple ID used on your rental iPhones. Until you do, trackers can't pair."))
        case .shared(let a, let p, let w)?:
            ("person.2", a > 0 ? String(localized: "Shared with the fleet Apple ID") : String(localized: "Invitation sent"),
             a > 0 ? (w ? String(localized: "\(a) Apple ID accepted. Rental iPhones signed in with it can pair.") : String(localized: "Accepted, but with read-only permission. Trackers must be allowed to make changes: open Manage sharing and change it."))
                   : String(localized: "\(p) invitation waiting. Open the link on a rental iPhone signed in with the fleet Apple ID."))
        }
    }
}

/// Wraps UICloudSharingController. UNVERIFIED on device.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let c = UICloudSharingController(share: share, container: container)
        c.availablePermissions = [.allowPrivate, .allowReadWrite]      // invitees only, and they must be able to write locations
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UICloudSharingController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? { "Rentro fleet" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    }
}
