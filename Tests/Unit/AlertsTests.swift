import Foundation
import SwiftData
import Testing
@testable import RentroAdmin

@MainActor
struct AlertsTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Makassar")!; return c }
    var noon: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! }

    @Test func alertsAreDerivedMostUrgentFirstWithStableKeys() throws {
        let e = try BookingTests.Env()
        let now = noon
        let h = BookingTests.Env.self      // keep type in scope for readability
        _ = h
        let b = try Fixtures.seed(e.ctx, owner: "u2", now: now)
        let id = b.id
        let rentals = try e.ctx.fetch(FetchDescriptor<Rental>(predicate: #Predicate { $0.businessID == id }))
        let a = Alerts.derive(rentals: rentals, now: now, calendar: cal)
        #expect(a.map(\.kind) == [.overdue, .dueToday, .pendingPickup])
        #expect(a.map(\.rental.code) == ["RNT-1025", "RNT-1027", "RNT-1026"])
        #expect(Alerts.derive(rentals: rentals, now: now, calendar: cal).map(\.key) == a.map(\.key))   // same state, same keys: no duplicates
    }

    @Test func completedRentalWithBalanceRaisesPaymentDue() throws {
        let e = try BookingTests.Env()
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(3600), now.addingTimeInterval(86400)), now: now)
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(3600))
        try e.ctx.confirmReturn(r, business: e.business, at: now.addingTimeInterval(86400))
        #expect(Alerts.derive(rentals: [r], now: now.addingTimeInterval(90000), calendar: cal).map(\.kind) == [.paymentDue])
        try e.ctx.recordPayment(r, amountIDR: 250_000, method: .cash)
        #expect(Alerts.derive(rentals: [r], now: now.addingTimeInterval(90000), calendar: cal).isEmpty)
    }

    @Test func markingReadIsIdempotent() throws {
        let e = try BookingTests.Env()
        try e.ctx.markRead(["overdue.1", "dueToday.2"], businessID: e.business.id)
        try e.ctx.markRead(["overdue.1"], businessID: e.business.id)
        #expect(try e.count(AlertRecord.self) == 2)
    }

    // MARK: reminders

    func rental(_ e: BookingTests.Env, _ s: RentalStatus, pickup: Date, ret: Date) -> Rental {
        let r = Rental(); r.status = s; r.pickupAt = pickup; r.expectedReturnAt = ret; r.customer = e.customer; r.device = e.device
        r.code = "RNT-\(Int.random(in: 1...999))"; e.ctx.insert(r); return r
    }

    @Test func remindersUseConfiguredLeadsAndSkipThePast() throws {
        let e = try BookingTests.Env()
        let now = noon, day = 86400.0
        let upcoming = rental(e, .reserved, pickup: now.addingTimeInterval(3 * day), ret: now.addingTimeInterval(4 * day))
        let soon = rental(e, .reserved, pickup: now.addingTimeInterval(3600), ret: now.addingTimeInterval(day))     // 24h lead already passed
        let active = rental(e, .active, pickup: now.addingTimeInterval(-day), ret: now.addingTimeInterval(5 * 3600))
        let plan = Reminders.plan(rentals: [upcoming, soon, active], prefs: ReminderPrefs(), now: now)
        #expect(plan.map(\.id) == ["rentro.return.\(active.id)", "rentro.overdue.\(active.id)", "rentro.pickup.\(upcoming.id)"])
        #expect(plan[0].fireAt == now.addingTimeInterval(3 * 3600))                    // 2h before the return (PRD default)
        #expect(plan[2].fireAt == now.addingTimeInterval(2 * day))                     // 24h before pickup (PRD default)
    }

    @Test func remindersRespectTogglesAndCap() throws {
        let e = try BookingTests.Env()
        let now = noon
        let r = rental(e, .active, pickup: now.addingTimeInterval(-3600), ret: now.addingTimeInterval(86400))
        var prefs = ReminderPrefs(); prefs.returned = false
        #expect(Reminders.plan(rentals: [r], prefs: prefs, now: now).map(\.id) == ["rentro.overdue.\(r.id)"])
        prefs.overdue = false
        #expect(Reminders.plan(rentals: [r], prefs: prefs, now: now).isEmpty)
        let many = (0..<70).map { rental(e, .reserved, pickup: now.addingTimeInterval(Double($0 + 3) * 86400), ret: now.addingTimeInterval(Double($0 + 4) * 86400)) }
        #expect(Reminders.plan(rentals: many, prefs: ReminderPrefs(), now: now).count == Reminders.maxPending)
    }
}
