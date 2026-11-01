import SwiftUI

#if DEBUG
/// Dev loopback only: shows the code the in-process server issued so a UI test can pair without a backend.
@MainActor @Observable final class DevPairingCode { var value: String? }
#endif

@main
struct RentroTrackerApp: App {
    @UIApplicationDelegateAdaptor(TrackerAppDelegate.self) private var appDelegate
    @State private var model: TrackerModel
    #if DEBUG
    @State private var devCode = DevPairingCode()
    #endif

    init() {
        #if DEBUG
        CloudKitSelfTest.runIfRequested()
        #endif
        var transport: TrackerTransport = UnconfiguredTransport()      // honest until the iCloud container exists
        if let id = CloudKitConfig.containerID { transport = CloudKitTrackerTransport(containerID: id) }   // unset until the container exists
        var fleet: FleetLinking = NoFleetLink()
        if let id = CloudKitConfig.containerID { fleet = CloudKitFleetLink(containerID: id) }
        var location: LocationProviding = CoreLocationProvider()
        var credentials = CredentialStore.keychain
        var persistence = TrackerPersistence.file
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let code = DevPairingCode()
        if args.contains("-trackerLoopback") {
            let server = LoopbackServer()
            transport = LoopbackTransport(server: server)
            credentials = .memory(); persistence = .none
            fleet = FakeFleetLink(value: args.contains("-fleetNotShared") ? .notShared : args.contains("-fleetNoAccount") ? .noICloudAccount : .linked)
            let grant: OSLocationAuth = args.contains("-fakeLocationDeny") ? .denied : .whenInUse
            location = FakeLocationProvider(grantOnRequest: grant)
            let unit = LoopbackServer.Unit(deviceID: UUID(), unitCode: "IP-001", businessName: "Papa Rental", deviceModel: "iPhone 15 Pro")
            Task { @MainActor in code.value = await server.issue(for: unit) }
        }
        _devCode = State(initialValue: code)
        #endif
        _model = State(initialValue: TrackerModel(transport: transport, location: location, credentials: credentials, fleet: fleet, persistence: persistence))
    }

    var body: some Scene {
        WindowGroup {
            let root = TrackerRootView().environment(model).tint(.brandSelected)
                .task { ShareAcceptance.handler = { await model.acceptFleetShare($0) } }
            #if DEBUG
            root.environment(devCode)
            #else
            root
            #endif
        }
    }
}
