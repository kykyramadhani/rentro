import SwiftUI

/// Dev loopback only: shows the code the in-process server issued so a UI test can pair without a backend. Stays nil in release.
@MainActor @Observable final class DevPairingCode { var value: String? }

extension TrackerModel {
    /// The tracker role's live wiring (CloudKit when configured), plus the dev loopback used by UI tests.
    #if DEBUG
    static func live() -> (TrackerModel, DevPairingCode) { let r = make(); return (r.0, r.1 ?? DevPairingCode()) }
    #else
    static func live() -> TrackerModel { make().0 }
    #endif

    private static func make() -> (TrackerModel, DevPairingCode?) {
        var transport: TrackerTransport = UnconfiguredTransport()      // honest until the iCloud container exists
        if let id = CloudKitConfig.containerID { transport = CloudKitTrackerTransport(containerID: id) }
        var fleet: FleetLinking = NoFleetLink()
        if let id = CloudKitConfig.containerID { fleet = CloudKitFleetLink(containerID: id) }
        var location: LocationProviding = CoreLocationProvider()
        var credentials = CredentialStore.keychain
        var persistence = TrackerPersistence.file
        var code: DevPairingCode?
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        code = DevPairingCode()
        if args.contains("-trackerLoopback") {
            let server = LoopbackServer()
            transport = LoopbackTransport(server: server)
            credentials = .memory(); persistence = .none
            fleet = FakeFleetLink(value: args.contains("-fleetNotShared") ? .notShared : args.contains("-fleetNoAccount") ? .noICloudAccount : .linked)
            let grant: OSLocationAuth = args.contains("-fakeLocationDeny") ? .denied : .whenInUse
            location = FakeLocationProvider(grantOnRequest: grant)
            let unit = LoopbackServer.Unit(deviceID: UUID(), unitCode: "IP-001", businessName: "Papa Rental", deviceModel: "iPhone 15 Pro")
            Task { @MainActor [code] in code?.value = await server.issue(for: unit) }
        }
        #endif
        return (TrackerModel(transport: transport, location: location, credentials: credentials, fleet: fleet, persistence: persistence), code)
    }
}
