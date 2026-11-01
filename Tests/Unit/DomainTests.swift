import AuthenticationServices
import Foundation
import SwiftData
import Testing
@testable import RentroAdmin

@MainActor
struct DomainTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Makassar")!; return c }
    // 2026-10-25 12:00 Makassar (UTC+8)
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! }

    /// Owns the container: a context must not outlive its ModelContainer.
    @MainActor final class Harness {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
        init() throws {
            container = try ModelContainer(for: Schema(versionedSchema: RentroSchemaV1.self), migrationPlan: RentroMigrationPlan.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    func rental(_ s: RentalStatus, ret: Date) -> Rental {
        let r = Rental(); r.status = s; r.pickupAt = now.addingTimeInterval(-86400); r.expectedReturnAt = ret; return r
    }

    @Test func moneyFormatsRupiah() {
        #expect(Money(idr: 250_000).formatted == "Rp 250.000")
        #expect(Money(idr: 1_250_500).formatted == "Rp 1.250.500")
    }

    @Test func badgeIsDerivedFromTime() {
        #expect(rental(.active, ret: now.addingTimeInterval(-60)).badge(now: now, calendar: cal) == .overdue)
        #expect(rental(.active, ret: now.addingTimeInterval(3600)).badge(now: now, calendar: cal) == .dueToday)
        #expect(rental(.active, ret: now.addingTimeInterval(2 * 86400)).badge(now: now, calendar: cal) == .active)
        #expect(rental(.reserved, ret: now.addingTimeInterval(86400)).badge(now: now, calendar: cal) == .upcoming)
        #expect(rental(.completed, ret: now.addingTimeInterval(-60)).badge(now: now, calendar: cal) == .returned)
    }

    @Test func dueTodayUsesBusinessTimezoneNotUTC() {
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 23, minute: 30))!
        let next = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0, minute: 30))!
        #expect(rental(.active, ret: late).badge(now: now, calendar: cal) == .dueToday)
        #expect(rental(.active, ret: next).badge(now: now, calendar: cal) == .active)
    }

    @Test func freshnessBoundaries() {
        #expect(LocationFreshness(age: nil) == .neverReported)
        #expect(LocationFreshness(age: 300) == .recent)
        #expect(LocationFreshness(age: 301) == .aging)
        #expect(LocationFreshness(age: 1800) == .aging)
        #expect(LocationFreshness(age: 1801) == .stale)
    }

    @Test func summaryAndActivityReconcileWithFixtures() throws {
        let h = try Harness()
        let b = try Fixtures.seed(h.ctx, owner: "u1", now: now)
        let id = b.id
        let devices = try h.ctx.fetch(FetchDescriptor<RentalDevice>(predicate: #Predicate { $0.businessID == id }))
        let rentals = try h.ctx.fetch(FetchDescriptor<Rental>(predicate: #Predicate { $0.businessID == id }))
        // 7 devices, 1 in maintenance (excluded), 3 active rentals, 1 overdue.
        #expect(Derive.summary(devices: devices, rentals: rentals, now: now, calendar: cal)
                == DashboardSummary(totalUnits: 6, rented: 3, available: 3, overdue: 1))
        let kinds = Derive.activity(rentals: rentals, now: now, calendar: cal).map { a -> String in
            switch a { case .pickup: "pickup"; case .return: "return"; case .overdue: "overdue" }
        }
        #expect(kinds == ["pickup", "return", "overdue"])
    }

    @Test func filtersComposeWithSearchAndClear() throws {
        let h = try Harness()
        let b = try Fixtures.seed(h.ctx, owner: "u1", now: now)
        let id = b.id
        let rentals = try h.ctx.fetch(FetchDescriptor<Rental>(predicate: #Predicate { $0.businessID == id }))
        let devices = try h.ctx.fetch(FetchDescriptor<RentalDevice>(predicate: #Predicate { $0.businessID == id }))
        #expect(Derive.rentals(rentals, filter: .overdue, query: "", now: now, calendar: cal).map(\.code) == ["RNT-1025"])
        #expect(Derive.rentals(rentals, filter: .overdue, query: "andi", now: now, calendar: cal).isEmpty)
        #expect(Derive.rentals(rentals, filter: .all, query: "andi", now: now, calendar: cal).map(\.code) == ["RNT-1024"])
        #expect(Derive.devices(devices, rentals: rentals, filter: .rented, query: "").count == 3)
    }

    // MARK: persistence + validation

    @Test func businessIsCreatedForOwnerAndValidated() throws {
        let h = try Harness()
        #expect(throws: DomainError.self) { try h.ctx.createBusiness(owner: "u1", BusinessInput(name: "   ")) }
        #expect(throws: DomainError.self) { try h.ctx.createBusiness(owner: "u1", BusinessInput(name: "A", dailyRateIDR: -1)) }
        let b = try h.ctx.createBusiness(owner: "u1", BusinessInput(name: " Kaye Rental ", timeZoneID: "Asia/Makassar", dailyRateIDR: 250_000))
        #expect(b.name == "Kaye Rental" && b.ownerAppleID == "u1" && b.defaultDailyRateIDR == 250_000)
        #expect(b.currencyCode == "IDR")
    }

    @Test func unitCodeIsUniquePerBusinessCaseInsensitive() throws {
        let h = try Harness()
        let a = UUID(), other = UUID()
        _ = try h.ctx.saveDevice(businessID: a, DeviceInput(unitCode: "ip-001", model: "iPhone 15"))
        #expect(throws: DomainError.duplicateUnitCode) { try h.ctx.saveDevice(businessID: a, DeviceInput(unitCode: "IP-001", model: "iPhone 13")) }
        // Same code in a different business is fine (two businesses, similar unit codes: AT-21 spirit).
        _ = try h.ctx.saveDevice(businessID: other, DeviceInput(unitCode: "IP-001", model: "iPhone 13"))
    }

    @Test func editingDeviceKeepsItsOwnCodeAndRetires() throws {
        let h = try Harness()
        let b = UUID()
        let d = try h.ctx.saveDevice(businessID: b, DeviceInput(unitCode: "IP-001", model: "iPhone 15"))
        let edited = try h.ctx.saveDevice(d, businessID: b, DeviceInput(unitCode: "IP-001", model: "iPhone 15 Pro", isActive: false))
        #expect(edited.id == d.id && edited.model == "iPhone 15 Pro" && edited.lifecycle == .retired)
        #expect(try h.ctx.fetch(FetchDescriptor<RentalDevice>()).count == 1)
        #expect(throws: DomainError.self) { try h.ctx.saveDevice(d, businessID: b, DeviceInput(unitCode: "", model: "x")) }
    }

    @Test func storedDataPersistsAcrossContexts() throws {
        let h = try Harness()
        _ = try h.ctx.createBusiness(owner: "u1", BusinessInput(name: "Kaye Rental"))
        #expect(try ModelContext(h.container).fetch(FetchDescriptor<Business>()).map(\.name) == ["Kaye Rental"])
    }

    // MARK: Sign in with Apple session

    func auth(stored: String?, state: ASAuthorizationAppleIDProvider.CredentialState) -> (AuthStore, Box) {
        let box = Box(value: stored)
        let s = SessionStorage(read: { box.value }, write: { box.value = $0 }, clear: { box.value = nil })
        return (AuthStore(storage: s, credentialState: { _ in state }), box)
    }
    final class Box { var value: String?; init(value: String?) { self.value = value } }

    @Test func restoreWithoutSessionIsSignedOut() async {
        let (a, _) = auth(stored: nil, state: .authorized)
        await a.restore()
        #expect(a.state == .signedOut)
    }

    @Test func restoreAuthorizedSignsIn() async {
        let (a, _) = auth(stored: "apple-1", state: .authorized)
        await a.restore()
        #expect(a.state == .signedIn(userID: "apple-1"))
    }

    @Test func revokedOrMissingCredentialClearsSession() async {
        for s in [ASAuthorizationAppleIDProvider.CredentialState.revoked, .notFound] {
            let (a, box) = auth(stored: "apple-1", state: s)
            await a.restore()
            #expect(a.state == .signedOut && box.value == nil)
        }
    }

    @Test func cancelIsNotAnErrorButOtherFailuresAre() {
        let (a, _) = auth(stored: nil, state: .authorized)
        a.handle(.failure(ASAuthorizationError(.canceled)))
        #expect(a.errorMessage == nil && a.state != .signedIn(userID: ""))
        a.handle(.failure(ASAuthorizationError(.failed)))
        #expect(a.errorMessage != nil)
    }

    @Test func authorizeStoresIdAndSignOutClearsIt() {
        let (a, box) = auth(stored: nil, state: .authorized)
        a.didAuthorize(userID: "apple-2")
        #expect(a.state == .signedIn(userID: "apple-2") && box.value == "apple-2")
        a.signOut()
        #expect(a.state == .signedOut && box.value == nil)
    }
}
