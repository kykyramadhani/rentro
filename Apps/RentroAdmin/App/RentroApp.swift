import SwiftData
import SwiftUI

@main
struct RentroApp: App {
    private let container: ModelContainer
    @State private var auth: AuthStore
    @State private var sync: LocationSync
    @State private var fleet = FleetSharingController()
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = Appearance.system

    init() {
        #if DEBUG
        CloudKitSelfTest.runIfRequested()
        #endif
        var memory = false
        var storage = SessionStorage.keychain
        #if DEBUG
        // Hermetic UI-test hooks: never touch the real Keychain or store. Dev-only.
        let args = ProcessInfo.processInfo.arguments
        memory = args.contains("-inMemoryStore")
        if args.contains("-uiTestSignedIn") || args.contains("-uiTestSignedOut") { storage = .memory }
        if args.contains("-resetBrandIntro") { UserDefaults.standard.removeObject(forKey: "brandIntroSeen") }   // first run again
        if args.contains("-skipBrandIntro") { UserDefaults.standard.set(true, forKey: "brandIntroSeen") }
        #endif
        let config = ModelConfiguration(isStoredInMemoryOnly: memory)
        // ponytail: a failed store open is unrecoverable here; surfaces as a crash at launch rather than silent data loss.
        container = try! ModelContainer(for: Schema(versionedSchema: RentroSchemaV1.self),
                                        migrationPlan: RentroMigrationPlan.self, configurations: config)
        let auth = AuthStore(storage: storage)
        _auth = State(initialValue: auth)
        var gateway: OwnerGateway = UnconfiguredOwnerGateway()          // honest until the iCloud container is configured
        #if DEBUG
        if args.contains("-adminLoopback") { gateway = LoopbackOwner(server: LoopbackServer()) }   // dev: issues codes, no phone can claim them
        #endif
        if let id = CloudKitConfig.containerID { gateway = CloudKitOwnerGateway(containerID: id) }   // unset until the container exists
        _sync = State(initialValue: LocationSync(gateway: gateway))
        #if DEBUG
        if args.contains("-uiTestSignedIn") {
            auth.didAuthorize(userID: "ui-test-user")
            if args.contains("-seedSample") { _ = try? Fixtures.seed(container.mainContext, owner: "ui-test-user") }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(sync)
                .environment(fleet)
                .environment(store)
                .tint(.brandSelected)
                .preferredColorScheme(appearance.scheme)
                .task { if auth.state == .resolving { await auth.restore() } }
        }
        .modelContainer(container)
    }
}

extension SessionStorage {
    /// Test-only in-memory slot.
    static var memory: SessionStorage {
        var value: String?
        return SessionStorage(read: { value }, write: { value = $0 }, clear: { value = nil })
    }
}

/// Route gate (PRD S00/3.1): resolving → Sign in → Business Setup → tabs. Nothing protected renders before auth resolves.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("brandIntroSeen") private var introSeen = false

    var body: some View {
        switch auth.state {
        case .resolving: Color.bgCanvas.ignoresSafeArea()
        case .signedOut:
            // First-run only, and only on the signed-out path: restoring a session or deep-linking never waits for it.
            if BrandIntroPolicy.shouldPlay(seen: introSeen, reduceMotion: reduceMotion) { AnimatedBrandIntro { introSeen = true } } else { SignInView() }
        case .signedIn(let id): SignedInRoot(userID: id).id(id)
        }
    }
}

private struct SignedInRoot: View {
    let userID: String
    @Query private var businesses: [Business]

    init(userID: String) {
        self.userID = userID
        _businesses = Query(filter: #Predicate<Business> { $0.ownerAppleID == userID })
    }

    var body: some View {
        if let business = businesses.first { MainTabs(business: business) } else { BusinessSetupView(userID: userID) }
    }
}

struct MainTabs: View {
    @Environment(AppStore.self) private var store
    let business: Business
    @Query private var rentals: [Rental]
    @AppStorage(NotificationKeys.pickup) private var pPickup = true
    @AppStorage(NotificationKeys.returned) private var pReturn = true
    @AppStorage(NotificationKeys.overdue) private var pOverdue = true
    @AppStorage(NotificationKeys.pickupLead) private var pPickupLead = 24 * 60
    @AppStorage(NotificationKeys.returnLead) private var pReturnLead = 120

    init(business: Business) {
        self.business = business
        let id = business.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
    }

    /// Changes whenever a booking or a preference changes, so reminders are re-planned (idempotently) without polling.
    private var reminderSignature: String {
        rentals.map { "\($0.id)\($0.statusRaw)\($0.pickupAt.timeIntervalSince1970)\($0.expectedReturnAt.timeIntervalSince1970)" }.sorted().joined()
            + "\(pPickup)\(pReturn)\(pOverdue)\(pPickupLead)\(pReturnLead)"
    }

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeView(business: business) }
            Tab("Rentals", systemImage: "list.clipboard", value: AppTab.rentals) { RentalsView(business: business) }
            Tab("Devices", systemImage: "iphone", value: AppTab.devices) { DevicesView(business: business) }
            Tab("Map", systemImage: "map", value: AppTab.map) { FleetMapView(business: business) }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView(business: business) }
        }
        .sheet(isPresented: $store.newRentalPresented) { NewRentalFlow(business: business) }
        .task(id: reminderSignature) {
            let prefs = ReminderPrefs(pickup: pPickup, returned: pReturn, overdue: pOverdue, pickupLeadMinutes: pPickupLead, returnLeadMinutes: pReturnLead)
            await Reminders.sync(Reminders.plan(rentals: rentals, prefs: prefs, now: .now))
        }
    }
}
