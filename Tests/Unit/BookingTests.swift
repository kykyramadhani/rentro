import Foundation
import SwiftData
import Testing
@testable import Rentro

@MainActor
struct BookingTests {
    let h = 3600.0, day = 86400.0
    let now = Date(timeIntervalSince1970: 1_792_900_000)   // fixed instant

    @MainActor final class Env {
        let container: ModelContainer
        var ctx: ModelContext { container.mainContext }
        let business: Business
        let customer: Customer
        let device: RentalDevice
        init(turnaround: Int = 0, grace: Int = 0) throws {
            container = try ModelContainer(for: Schema(versionedSchema: RentroSchemaV1.self), migrationPlan: RentroMigrationPlan.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            let c = container.mainContext
            business = try c.createBusiness(owner: "u1", BusinessInput(name: "B", timeZoneID: "Asia/Makassar", dailyRateIDR: 250_000))
            business.turnaroundMinutes = turnaround
            business.lateGraceMinutes = grace
            device = try c.saveDevice(businessID: business.id, DeviceInput(unitCode: "IP-001", model: "iPhone 15", dailyRateIDR: 250_000, depositIDR: 500_000))
            customer = Customer(); customer.businessID = business.id; customer.fullName = "Andi"; c.insert(customer)
            try c.save()
        }
        func input(_ pickup: Date, _ ret: Date, discount: Int = 0, pay: Int = 0, deposit: Int = 0, key: String = UUID().uuidString) -> RentalInput {
            RentalInput(customer: customer, device: device, pickupAt: pickup, expectedReturnAt: ret, discountIDR: discount,
                        initialPaymentIDR: pay, depositPaidIDR: deposit, idempotencyKey: key)
        }
        func count<T: PersistentModel>(_ t: T.Type) throws -> Int { try ctx.fetchCount(FetchDescriptor<T>()) }
    }

    // MARK: pricing

    @Test func billableDaysCountEveryStartedDayMinimumOne() {
        let t = now
        #expect(Billing.billableDays(from: t, to: t.addingTimeInterval(60)) == 1)
        #expect(Billing.billableDays(from: t, to: t.addingTimeInterval(day)) == 1)
        #expect(Billing.billableDays(from: t, to: t.addingTimeInterval(day + 60)) == 2)
        #expect(Billing.billableDays(from: t, to: t.addingTimeInterval(49 * h)) == 3)
        #expect(Billing.quote(dailyRateIDR: 250_000, from: t, to: t.addingTimeInterval(49 * h)).subtotalIDR == 750_000)
    }

    @Test func lateFeeChargesStartedDaysAfterGrace() {
        let due = now
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due, graceMinutes: 0) == 0)
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due.addingTimeInterval(60), graceMinutes: 0) == 250_000)
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due.addingTimeInterval(30 * 60), graceMinutes: 60) == 0)
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due.addingTimeInterval(25 * h), graceMinutes: 0) == 500_000)
    }

    // MARK: create (AT-03, AT-04, AT-22, AT-25)

    @Test func createsOneReservedRentalWithSnapshotAndPayments() throws {
        let e = try Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(h + 2 * day), pay: 100_000, deposit: 500_000), now: now)
        #expect(r.status == .reserved && r.code == "RNT-1024")
        #expect(r.billableUnits == 2 && r.subtotalIDR == 500_000 && r.dailyRateIDR == 250_000)
        #expect(r.totalChargesIDR == 500_000)              // deposit is not a charge
        #expect(r.amountPaidIDR == 100_000 && r.balanceDueIDR == 400_000 && r.paymentState == .partial)
        #expect(r.depositHeldIDR == 500_000)
        #expect(try e.count(Rental.self) == 1 && e.count(PaymentEntry.self) == 2 && e.count(RentalEvent.self) == 1)
    }

    @Test func retryWithSameKeyCreatesExactlyOneRental() throws {
        let e = try Env()
        let i = e.input(now.addingTimeInterval(h), now.addingTimeInterval(day), pay: 50_000, key: "k1")
        let a = try e.ctx.createRental(business: e.business, i, now: now)
        let b = try e.ctx.createRental(business: e.business, i, now: now)
        #expect(a.id == b.id)
        #expect(try e.count(Rental.self) == 1 && e.count(PaymentEntry.self) == 1)
    }

    @Test func overlappingBookingIsRejectedWithNoPartialRecords() throws {
        let e = try Env()
        try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(3 * day)), now: now)
        #expect(throws: DomainError.conflict) {
            try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(day), now.addingTimeInterval(4 * day), pay: 100_000, deposit: 500_000), now: now)
        }
        #expect(try e.count(Rental.self) == 1 && e.count(PaymentEntry.self) == 0 && e.count(RentalEvent.self) == 1)
    }

    @Test func handoverAtExactBoundaryIsAllowedUnlessTurnaroundBlocksIt() throws {
        let a = try Env(turnaround: 0)
        let end = now.addingTimeInterval(2 * day)
        try a.ctx.createRental(business: a.business, a.input(now.addingTimeInterval(h), end), now: now)
        _ = try a.ctx.createRental(business: a.business, a.input(end, end.addingTimeInterval(day)), now: now)   // half-open: no overlap

        let b = try Env(turnaround: 60)
        try b.ctx.createRental(business: b.business, b.input(now.addingTimeInterval(h), end), now: now)
        #expect(throws: DomainError.conflict) { try b.ctx.createRental(business: b.business, b.input(end, end.addingTimeInterval(day)), now: now) }
        _ = try b.ctx.createRental(business: b.business, b.input(end.addingTimeInterval(h), end.addingTimeInterval(day)), now: now)
    }

    @Test func invalidBookingsAreRejected() throws {
        let e = try Env()
        let p = now.addingTimeInterval(h)
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, e.input(p, p), now: now) }                         // end == start
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(-day), p), now: now) } // past pickup
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, e.input(p, p.addingTimeInterval(day), discount: 250_001), now: now) }
        #expect(throws: DomainError.overpayment) { try e.ctx.createRental(business: e.business, e.input(p, p.addingTimeInterval(day), pay: 250_001), now: now) }
        e.device.lifecycle = .maintenance                                                                                                   // AT-22
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, e.input(p, p.addingTimeInterval(day)), now: now) }
        e.device.lifecycle = .enabled
        let stranger = Customer(); stranger.businessID = UUID(); e.ctx.insert(stranger)
        var cross = e.input(p, p.addingTimeInterval(day)); cross.customer = stranger
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, cross, now: now) }
        #expect(try e.count(Rental.self) == 0)
    }

    // MARK: lifecycle (AT-05, AT-09, AT-10)

    @Test func pickupActivatesAndOnlyOnce() throws {
        let e = try Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now)
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(2 * h))
        #expect(r.status == .active && r.actualPickupAt == now.addingTimeInterval(2 * h))
        #expect(Derive.status(of: e.device, rentals: [r]) == .rented)
        #expect(throws: DomainError.self) { try e.ctx.confirmPickup(r) }
    }

    @Test func cancelReleasesTheSlotButOnlyForReservations() throws {
        let e = try Env()
        let p = now.addingTimeInterval(h), q = now.addingTimeInterval(2 * day)
        let r = try e.ctx.createRental(business: e.business, e.input(p, q), now: now)
        #expect(throws: DomainError.self) { try e.ctx.cancelReservation(r, reason: "  ") }
        try e.ctx.cancelReservation(r, reason: "Customer changed plans")
        #expect(r.status == .cancelled && r.cancelReason == "Customer changed plans")
        _ = try e.ctx.createRental(business: e.business, e.input(p, q), now: now)           // slot is free again
        #expect(try e.count(Rental.self) == 2)                                              // history kept
        let active = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(3 * day), now.addingTimeInterval(4 * day)), now: now)
        try e.ctx.confirmPickup(active)
        #expect(throws: DomainError.self) { try e.ctx.cancelReservation(active, reason: "x") }
    }

    @Test func extendIsBlockedByNextReservationAndUsesTheRateSnapshot() throws {
        let e = try Env()
        let a = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now)
        try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(3 * day), now.addingTimeInterval(4 * day)), now: now)
        try e.ctx.confirmPickup(a)
        #expect(throws: DomainError.conflict) { try e.ctx.extendRental(a, business: e.business, to: now.addingTimeInterval(3 * day + h)) }
        #expect(throws: DomainError.self) { try e.ctx.extendRental(a, business: e.business, to: now) }   // not later
        e.device.dailyRateIDR = 999_000                                                                    // later rate change must not leak
        try e.ctx.extendRental(a, business: e.business, to: now.addingTimeInterval(2 * day))
        #expect(a.billableUnits == 2 && a.subtotalIDR == 500_000)
        #expect((a.events ?? []).contains { $0.type == "extended" })
    }

    // MARK: return, late fee, payments (AT-07, AT-25)

    @Test func returnComputesLateFeeAndBalanceAndKeepsDepositHeld() throws {
        let e = try Env()
        let due = now.addingTimeInterval(day)
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), due, pay: 250_000, deposit: 500_000), now: now)
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(h))
        #expect(throws: DomainError.self) { try e.ctx.confirmReturn(r, business: e.business, at: now) }                              // before pickup
        #expect(throws: DomainError.self) { try e.ctx.confirmReturn(r, business: e.business, at: due, damageFeeIDR: 50_000) }         // reason needed
        let s = try e.ctx.confirmReturn(r, business: e.business, at: due.addingTimeInterval(26 * h), damageFeeIDR: 50_000, damageReason: "Cracked screen")
        #expect(s == ReturnSummary(lateFeeIDR: 500_000, damageFeeIDR: 50_000, balanceDueIDR: 550_000, depositHeldIDR: 500_000))
        #expect(r.status == .completed && r.actualReturnAt != nil)
        #expect(Derive.status(of: e.device, rentals: [r]) == .available)
    }

    @Test func paymentIsIdempotentPositiveAndOverpaymentNeedsConfirmation() throws {
        let e = try Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now)
        try e.ctx.recordPayment(r, amountIDR: 100_000, method: .bankTransfer, reference: "TRX1", key: "p1")
        try e.ctx.recordPayment(r, amountIDR: 100_000, method: .bankTransfer, reference: "TRX1", key: "p1")   // double tap
        #expect(r.amountPaidIDR == 100_000 && (r.payments ?? []).count == 1)
        #expect(throws: DomainError.self) { try e.ctx.recordPayment(r, amountIDR: 0, method: .cash) }
        #expect(throws: DomainError.overpayment) { try e.ctx.recordPayment(r, amountIDR: 200_000, method: .cash) }
        try e.ctx.recordPayment(r, amountIDR: 150_000, method: .cash)
        #expect(r.paymentState == .paid)
        try e.ctx.recordPayment(r, amountIDR: 10_000, method: .cash, allowOverpayment: true)
        #expect(r.paymentState == .overpaid && r.balanceDueIDR == -10_000)
    }

    // MARK: deposit (AT-08, AT-29)

    @Test func depositSettlementReducesLiabilityNotIncome() throws {
        let e = try Env()
        let due = now.addingTimeInterval(day)
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), due, pay: 250_000, deposit: 500_000), now: now)
        #expect(throws: DomainError.self) { try e.ctx.settleDeposit(r, refundIDR: 100_000, method: .cash) }          // not returned yet
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(h))
        try e.ctx.confirmReturn(r, business: e.business, at: due)
        let paidBefore = r.amountPaidIDR
        #expect(throws: DomainError.self) { try e.ctx.settleDeposit(r, refundIDR: 600_000, method: .cash) }          // more than held
        #expect(throws: DomainError.self) { try e.ctx.settleDeposit(r, refundIDR: 100_000, deductionIDR: 50_000, method: .cash) }   // reason needed
        try e.ctx.settleDeposit(r, refundIDR: 300_000, deductionIDR: 200_000, reason: "Replaced charger", method: .cash, key: "s1")
        try e.ctx.settleDeposit(r, refundIDR: 300_000, deductionIDR: 200_000, reason: "Replaced charger", method: .cash, key: "s1")   // retry
        #expect(r.depositHeldIDR == 0 && r.amountPaidIDR == paidBefore)
        #expect((r.payments ?? []).filter { $0.category == .depositDeduction }.map(\.reference) == ["Replaced charger"])
    }

    // MARK: customers (AT-26)

    @Test func phoneNumbersNormalizeToPlus62() {
        #expect(Phone.normalize("0812-3456-7890") == "+6281234567890")
        #expect(Phone.normalize("+62 812 3456 7890") == "+6281234567890")
        #expect(Phone.normalize("62812 3456 7890") == "+6281234567890")
        #expect(Phone.normalize("123") == nil && Phone.normalize("") == nil)
        #expect(Phone.display("+6281234567890") == "+62 812 3456 7890")
    }

    @Test func customersAreValidatedAndDuplicateNamesAreKeptApart() throws {
        let e = try Env()
        #expect(throws: DomainError.self) { try e.ctx.saveCustomer(businessID: e.business.id, name: " ", phone: "") }
        #expect(throws: DomainError.self) { try e.ctx.saveCustomer(businessID: e.business.id, name: "A", phone: "12") }
        let a = try e.ctx.saveCustomer(businessID: e.business.id, name: "Made Arta", phone: "0813 1122 3344")
        let b = try e.ctx.saveCustomer(businessID: e.business.id, name: "Made Arta", phone: "0812 9999 0000")
        #expect(a.id != b.id && a.phone != b.phone)       // no silent merge
        _ = try e.ctx.saveCustomer(a, businessID: e.business.id, name: "Made A.", phone: "")
        #expect(a.fullName == "Made A." && a.phone == "")
    }

    // MARK: maintenance (S17, AT-22)

    @Test func maintenanceNeedsAnIssueAndIsBlockedByOpenRentals() throws {
        let e = try Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now)
        #expect(throws: DomainError.self) { try e.ctx.setDeviceStatus(e.device, .maintenance, note: "Cracked screen") }   // open reservation
        try e.ctx.cancelReservation(r, reason: "Moved")
        #expect(throws: DomainError.self) { try e.ctx.setDeviceStatus(e.device, .maintenance, note: " ") }               // issue required
        try e.ctx.setDeviceStatus(e.device, .maintenance, note: "Cracked screen", now: now)
        #expect(e.device.lifecycle == .maintenance && e.device.maintenanceNote == "Cracked screen")
        #expect(throws: DomainError.self) { try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now) }
        try e.ctx.setDeviceStatus(e.device, .enabled)
        #expect(e.device.lifecycle == .enabled && e.device.maintenanceNote.isEmpty)
        _ = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), now.addingTimeInterval(day)), now: now)
    }
}
