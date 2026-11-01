import Foundation
import SwiftData

struct Quote: Equatable {
    var billableUnits: Int
    var dailyRateIDR: Int
    var subtotalIDR: Int { billableUnits * dailyRateIDR }
}

/// Pure pricing (PRD 4.4). Whole rupiah only.
enum Billing {
    /// Every started 24h period counts as a day, minimum 1.
    static func billableDays(from: Date, to: Date) -> Int {
        let minutes = Int((to.timeIntervalSince(from) / 60).rounded(.up))
        return max(1, (minutes + 1439) / 1440)
    }

    static func quote(dailyRateIDR: Int, from: Date, to: Date) -> Quote {
        Quote(billableUnits: billableDays(from: from, to: to), dailyRateIDR: dailyRateIDR)
    }

    /// Every started day (or hour) past expected return, after the grace period. `amountIDR` 0 falls back to the device rate.
    // ponytail: hourly fallback is dailyRate / 24 in whole rupiah (rounds down); set an explicit hourly amount for exactness.
    static func lateFee(dailyRateIDR: Int, expectedReturn: Date, actualReturn: Date, graceMinutes: Int,
                        unit: LateFeeUnit = .day, amountIDR: Int = 0) -> Int {
        let lateMinutes = Int((actualReturn.timeIntervalSince(expectedReturn) / 60).rounded(.up)) - graceMinutes
        guard lateMinutes > 0 else { return 0 }
        switch unit {
        case .day: return ((lateMinutes + 1439) / 1440) * (amountIDR > 0 ? amountIDR : dailyRateIDR)
        case .hour: return ((lateMinutes + 59) / 60) * (amountIDR > 0 ? amountIDR : dailyRateIDR / 24)
        }
    }
}

struct RentalInput {
    var customer: Customer
    var device: RentalDevice
    var pickupAt: Date
    var expectedReturnAt: Date
    var discountIDR = 0
    var initialPaymentIDR = 0
    var depositPaidIDR = 0
    var method = PaymentMethod.cash
    var paymentNote = ""
    var idempotencyKey = UUID().uuidString
}

struct ReturnSummary: Equatable {
    var lateFeeIDR: Int
    var damageFeeIDR: Int
    var balanceDueIDR: Int
    var depositHeldIDR: Int
}

extension ModelContext {
    /// First reserved/active rental on `device` that overlaps [from, to) once the turnaround buffer is added (PRD 4.3).
    func conflictingRental(device: RentalDevice, from: Date, to: Date, turnaroundMinutes: Int, excluding: UUID? = nil) -> Rental? {
        let buffer = TimeInterval(turnaroundMinutes * 60)
        return (device.rentals ?? []).first { r in
            r.id != excluding && (r.status == .reserved || r.status == .active)
                && from < r.expectedReturnAt.addingTimeInterval(buffer) && r.pickupAt < to.addingTimeInterval(buffer)
        }
    }

    /// Atomic: all checks run before anything is inserted; a failed save rolls back (PRD S08).
    @discardableResult
    func createRental(business: Business, _ i: RentalInput, now: Date = .now) throws -> Rental {
        let key = i.idempotencyKey
        let bid = business.id
        if let existing = try fetch(FetchDescriptor<Rental>(predicate: #Predicate { $0.businessID == bid && $0.idempotencyKey == key })).first {
            return existing   // double-tap / retry: exactly one rental (PRD S08, AT-25 spirit)
        }
        guard i.customer.businessID == bid, i.device.businessID == bid else { throw DomainError.invalid(String(localized: "Choose a customer and device from this business.")) }
        guard i.expectedReturnAt > i.pickupAt else { throw DomainError.invalid(String(localized: "Return must be after pickup.")) }
        guard i.pickupAt >= now.addingTimeInterval(-300) else { throw DomainError.invalid(String(localized: "Pickup time is in the past.")) }
        guard i.device.lifecycle == .enabled else { throw DomainError.invalid(String(localized: "This iPhone is not available for rental.")) }
        let q = Billing.quote(dailyRateIDR: i.device.dailyRateIDR, from: i.pickupAt, to: i.expectedReturnAt)
        guard (0...q.subtotalIDR).contains(i.discountIDR) else { throw DomainError.invalid(String(localized: "Discount must be between Rp 0 and the subtotal.")) }
        guard i.initialPaymentIDR >= 0, (0...i.device.depositIDR).contains(i.depositPaidIDR) else {
            throw DomainError.invalid(String(localized: "Check the payment and deposit amounts."))
        }
        guard i.initialPaymentIDR <= q.subtotalIDR - i.discountIDR else { throw DomainError.overpayment }
        if conflictingRental(device: i.device, from: i.pickupAt, to: i.expectedReturnAt, turnaroundMinutes: business.turnaroundMinutes) != nil {
            throw DomainError.conflict
        }

        let count = try fetchCount(FetchDescriptor<Rental>(predicate: #Predicate { $0.businessID == bid }))
        let r = Rental()
        r.businessID = bid
        r.code = "RNT-\(1024 + count)"
        r.customer = i.customer
        r.device = i.device
        r.pickupAt = i.pickupAt
        r.expectedReturnAt = i.expectedReturnAt
        r.dailyRateIDR = i.device.dailyRateIDR
        r.depositIDR = i.device.depositIDR
        r.billableUnits = q.billableUnits
        r.subtotalIDR = q.subtotalIDR
        r.discountIDR = i.discountIDR
        r.lateGraceMinutes = business.lateGraceMinutes
        r.lateFeeUnitRaw = business.lateFeeUnitRaw
        r.lateFeeAmountIDR = business.lateFeeAmountIDR
        r.idempotencyKey = key
        insert(r)
        if i.initialPaymentIDR > 0 { addEntry(r, .rentalPayment, i.initialPaymentIDR, i.method, i.paymentNote, now, "\(key).pay") }
        if i.depositPaidIDR > 0 { addEntry(r, .depositReceived, i.depositPaidIDR, i.method, "Security deposit", now, "\(key).dep") }
        addEvent(r, "created", "")
        do { try save() } catch { rollback(); throw error }
        return r
    }

    func confirmPickup(_ r: Rental, at: Date = .now, note: String = "") throws {
        guard r.status == .reserved else { throw DomainError.invalid(String(localized: "Only a reserved rental can be picked up.")) }
        if let d = r.device, (d.rentals ?? []).contains(where: { $0.id != r.id && $0.status == .active }) {
            throw DomainError.invalid(String(localized: "This iPhone is still out with another rental."))
        }
        r.status = .active
        r.actualPickupAt = at
        addEvent(r, "pickup", note.trimmingCharacters(in: .whitespacesAndNewlines))
        try save()
    }

    func extendRental(_ r: Rental, business: Business, to newReturn: Date) throws {
        guard r.status == .active else { throw DomainError.invalid(String(localized: "Only an active rental can be extended.")) }
        guard newReturn > r.expectedReturnAt else { throw DomainError.invalid(String(localized: "The new return must be later than the current one.")) }
        if let d = r.device, conflictingRental(device: d, from: r.pickupAt, to: newReturn, turnaroundMinutes: business.turnaroundMinutes, excluding: r.id) != nil {
            throw DomainError.conflict
        }
        let old = r.expectedReturnAt
        r.expectedReturnAt = newReturn
        r.billableUnits = Billing.billableDays(from: r.pickupAt, to: newReturn)
        r.subtotalIDR = r.billableUnits * r.dailyRateIDR     // existing rate snapshot, not today's rate
        addEvent(r, "extended", "\(old.ISO8601Format()) → \(newReturn.ISO8601Format())")
        try save()
    }

    func cancelReservation(_ r: Rental, reason: String) throws {
        guard r.status == .reserved else { throw DomainError.invalid(String(localized: "Only a reserved rental can be cancelled. Use Return for an active one.")) }
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { throw DomainError.invalid(String(localized: "Enter a reason for the cancellation.")) }
        r.status = .cancelled
        r.cancelReason = reason
        addEvent(r, "cancelled", reason)
        try save()
    }

    @discardableResult
    func confirmReturn(_ r: Rental, business: Business, at: Date = .now, damageFeeIDR: Int = 0, damageReason: String = "",
                       conditionNote: String = "", needsMaintenance: Bool = false) throws -> ReturnSummary {
        guard r.status == .active else { throw DomainError.invalid(String(localized: "Only an active rental can be returned.")) }
        guard at >= (r.actualPickupAt ?? r.pickupAt) else { throw DomainError.invalid(String(localized: "Return time cannot be before pickup.")) }
        guard damageFeeIDR >= 0 else { throw DomainError.invalid(String(localized: "Damage charge cannot be negative.")) }
        let reason = damageReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard damageFeeIDR == 0 || !reason.isEmpty else { throw DomainError.invalid(String(localized: "Enter a reason for the damage charge.")) }
        // Late-fee policy comes from the rental's own snapshot, not today's settings.
        r.lateFeeIDR = Billing.lateFee(dailyRateIDR: r.dailyRateIDR, expectedReturn: r.expectedReturnAt, actualReturn: at,
                                       graceMinutes: r.lateGraceMinutes, unit: r.lateFeeUnit, amountIDR: r.lateFeeAmountIDR)
        r.damageFeeIDR = damageFeeIDR
        r.actualReturnAt = at
        r.status = .completed
        let condition = conditionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        addEvent(r, "returned", [damageFeeIDR > 0 ? String(localized: "Damage: \(reason)") : "", condition].filter { !$0.isEmpty }.joined(separator: " · "))
        if needsMaintenance, let d = r.device {      // device state is independent of rental state (PRD 4.2)
            d.lifecycle = .maintenance
            d.maintenanceSince = at
            d.maintenanceNote = condition
        }
        try save()
        return ReturnSummary(lateFeeIDR: r.lateFeeIDR, damageFeeIDR: r.damageFeeIDR, balanceDueIDR: r.balanceDueIDR, depositHeldIDR: r.depositHeldIDR)
    }

    /// Manual payment only (no gateway, PRD 4.5). Same `key` twice records one entry.
    @discardableResult
    func recordPayment(_ r: Rental, amountIDR: Int, method: PaymentMethod, reference: String = "", paidAt: Date = .now,
                       key: String = UUID().uuidString, allowOverpayment: Bool = false) throws -> PaymentEntry {
        if let dup = (r.payments ?? []).first(where: { $0.idempotencyKey == key }) { return dup }
        guard r.status != .cancelled else { throw DomainError.invalid(String(localized: "This rental was cancelled.")) }
        guard amountIDR > 0 else { throw DomainError.invalid(String(localized: "Enter an amount greater than zero.")) }
        if amountIDR > max(r.balanceDueIDR, 0), !allowOverpayment { throw DomainError.overpayment }
        let e = addEntry(r, .rentalPayment, amountIDR, method, reference, paidAt, key)
        try save()
        return e
    }

    /// Refund and/or documented deduction against the held deposit. Never touches rental income (PRD S26).
    func settleDeposit(_ r: Rental, refundIDR: Int, deductionIDR: Int = 0, reason: String = "", method: PaymentMethod,
                       key: String = UUID().uuidString) throws {
        if (r.payments ?? []).contains(where: { $0.idempotencyKey.hasPrefix(key) }) { return }
        guard r.status == .completed || r.status == .cancelled else { throw DomainError.invalid(String(localized: "Settle the deposit after the rental is returned or cancelled.")) }
        guard refundIDR >= 0, deductionIDR >= 0, refundIDR + deductionIDR > 0 else { throw DomainError.invalid(String(localized: "Enter a refund or a deduction.")) }
        guard refundIDR + deductionIDR <= r.depositHeldIDR else { throw DomainError.invalid(String(localized: "That is more than the deposit held.")) }
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard deductionIDR == 0 || !reason.isEmpty else { throw DomainError.invalid(String(localized: "Enter a reason for the deduction.")) }
        if refundIDR > 0 { addEntry(r, .depositRefunded, refundIDR, method, "Deposit refund", .now, "\(key).refund") }
        if deductionIDR > 0 { addEntry(r, .depositDeduction, deductionIDR, method, reason, .now, "\(key).deduct") }
        try save()
    }

    // MARK: helpers

    @discardableResult
    private func addEntry(_ r: Rental, _ c: PaymentCategory, _ amount: Int, _ m: PaymentMethod, _ ref: String, _ at: Date, _ key: String) -> PaymentEntry {
        let e = PaymentEntry()
        e.businessID = r.businessID
        e.rental = r
        e.category = c
        e.amountIDR = amount
        e.method = m
        e.reference = ref
        e.paidAt = at
        e.idempotencyKey = key
        insert(e)
        return e
    }

    private func addEvent(_ r: Rental, _ type: String, _ note: String) {
        let e = RentalEvent()
        e.businessID = r.businessID
        e.rental = r
        e.type = type
        e.note = note
        insert(e)
    }
}
