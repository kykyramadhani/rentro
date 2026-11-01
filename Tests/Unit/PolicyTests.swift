import Foundation
import SwiftData
import Testing
@testable import RentroAdmin

@MainActor
struct PolicyTests {
    let h = 3600.0, day = 86400.0
    let now = Date(timeIntervalSince1970: 1_792_900_000)
    let due = Date(timeIntervalSince1970: 1_792_900_000 + 86400)

    // MARK: late-fee unit and amount (PRD S30)

    @Test func lateFeePerDayUsesCustomAmountOrDeviceRate() {
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due.addingTimeInterval(60), graceMinutes: 0, unit: .day, amountIDR: 100_000) == 100_000)
        #expect(Billing.lateFee(dailyRateIDR: 250_000, expectedReturn: due, actualReturn: due.addingTimeInterval(25 * h), graceMinutes: 0, unit: .day, amountIDR: 0) == 500_000)
    }

    @Test func lateFeePerHourCountsStartedHoursAfterGrace() {
        func fee(_ minutesLate: Double, grace: Int = 0, amount: Int = 25_000) -> Int {
            Billing.lateFee(dailyRateIDR: 240_000, expectedReturn: due, actualReturn: due.addingTimeInterval(minutesLate * 60),
                            graceMinutes: grace, unit: .hour, amountIDR: amount)
        }
        #expect(fee(0) == 0)
        #expect(fee(1) == 25_000)
        #expect(fee(60) == 25_000)
        #expect(fee(61) == 50_000)
        #expect(fee(90, grace: 30) == 25_000)          // 60 minutes beyond grace
        #expect(fee(61, amount: 0) == 20_000)          // 240.000 / 24 = 10.000 per hour, 2 started hours
    }

    @Test func returnUsesTheRentalsPolicySnapshotNotTodaysSettings() throws {
        let e = try BookingTests.Env()
        e.business.lateGraceMinutes = 0
        e.business.lateFeeUnit = .day
        e.business.lateFeeAmountIDR = 100_000
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), due), now: now)
        #expect(r.lateFeeAmountIDR == 100_000 && r.lateFeeUnit == .day)
        // Owner changes the policy after booking: this rental must not be affected.
        e.business.lateFeeUnit = .hour
        e.business.lateFeeAmountIDR = 1_000_000
        e.business.lateGraceMinutes = 600
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(h))
        let s = try e.ctx.confirmReturn(r, business: e.business, at: due.addingTimeInterval(5 * h))
        #expect(s.lateFeeIDR == 100_000)
    }

    // MARK: return + maintenance (PRD S11, 4.2)

    @Test func returnCanSendTheDeviceToMaintenanceAndBlockFurtherBooking() throws {
        let e = try BookingTests.Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), due), now: now)
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(h))
        try e.ctx.confirmReturn(r, business: e.business, at: due, conditionNote: "Cracked back glass", needsMaintenance: true)
        #expect(r.status == .completed)                                   // rental state and device state are independent
        #expect(e.device.lifecycle == .maintenance && e.device.maintenanceNote == "Cracked back glass")
        #expect((r.events ?? []).contains { $0.type == "returned" && $0.note.contains("Cracked back glass") })
        #expect(Derive.status(of: e.device, rentals: [r]) == .maintenance)
        #expect(throws: DomainError.self) {
            try e.ctx.createRental(business: e.business, e.input(due.addingTimeInterval(day), due.addingTimeInterval(2 * day)), now: now)
        }
    }

    @Test func returnWithoutFlagLeavesDeviceAvailable() throws {
        let e = try BookingTests.Env()
        let r = try e.ctx.createRental(business: e.business, e.input(now.addingTimeInterval(h), due), now: now)
        try e.ctx.confirmPickup(r, at: now.addingTimeInterval(h))
        try e.ctx.confirmReturn(r, business: e.business, at: due)
        #expect(e.device.lifecycle == .enabled)
    }

    // MARK: Rupiah input and date stamp

    @Test func rupiahFieldParsesDigitsAndGroupsWithDots() {
        #expect(Rupiah.parse("250.000") == 250_000)
        #expect(Rupiah.parse("Rp 1.250.500") == 1_250_500)
        #expect(Rupiah.parse("") == 0 && Rupiah.parse("abc") == 0)
        #expect(Rupiah.parse("99999999999999999999") == 999_999_999_999)     // capped at 12 digits, no overflow
        #expect(Rupiah.group(250_000) == "250.000")
        #expect(Rupiah.group(0, blankWhenZero: true) == "" && Rupiah.group(0) == "0")
        #expect(Rupiah.group(Rupiah.parse("1250500")) == "1.250.500")
    }

    @Test func stampShowsDayMonthTimeInBusinessTimezoneAndYearOnlyWhenDifferent() {
        let tz = TimeZone(identifier: "Asia/Makassar")!
        let en = Locale(identifier: "en_US")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 10))!
        let nowSameYear = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let nowNextYear = cal.date(from: DateComponents(year: 2027, month: 1, day: 5, hour: 12))!
        let same = d.stamp(tz, now: nowSameYear, locale: en)
        #expect(same.contains("Oct") && same.contains("24") && same.contains("·") && !same.contains("2026"))
        #expect(d.stamp(tz, now: nowNextYear, locale: en).contains("2026"))
        // 23:30 UTC on the 24th is already the 25th in Makassar (UTC+8): the business timezone wins.
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7, minute: 30))!
        #expect(late.stamp(tz, now: nowSameYear, locale: en).contains("25"))
    }
}
