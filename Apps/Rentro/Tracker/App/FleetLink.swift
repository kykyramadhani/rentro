import CloudKit
import Foundation
import UIKit

/// The tracker phone's link to the owner's shared "Fleet" zone. UNVERIFIED against iCloud (no container yet).
@MainActor protocol FleetLinking {
    func access() async -> FleetAccess
    func accept(_ metadata: CKShare.Metadata) async throws
}

/// Release builds without a container: access is "not configured", honestly.
struct NoFleetLink: FleetLinking {
    func access() async -> FleetAccess { .notConfigured }
    func accept(_ metadata: CKShare.Metadata) async throws { throw TransportError.notConfigured }
}

struct CloudKitFleetLink: FleetLinking {
    let container: CKContainer
    init(containerID: String) { container = CKContainer(identifier: containerID) }

    func access() async -> FleetAccess {
        guard let status = try? await container.accountStatus(), status == .available else {
            return FleetSharing.access(configured: true, accountAvailable: false, zoneVisible: false)
        }
        let visible = ((try? await container.fleetZone()) ?? nil) != nil
        return FleetSharing.access(configured: true, accountAvailable: true, zoneVisible: visible)
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        do { _ = try await container.accept(metadata) } catch { throw CKSchema.transportError(error) }
    }
}

#if DEBUG
struct FakeFleetLink: FleetLinking {
    var value: FleetAccess = .linked
    func access() async -> FleetAccess { value }
    func accept(_ metadata: CKShare.Metadata) async throws {}
}
#endif

/// iOS hands a tapped share link to the scene delegate; this forwards it to whoever is listening (the model).
@MainActor enum ShareAcceptance { static var handler: ((CKShare.Metadata) async -> Void)? }

final class TrackerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = TrackerSceneDelegate.self
        return c
    }
}

final class TrackerSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await ShareAcceptance.handler?(metadata) }
    }
}
