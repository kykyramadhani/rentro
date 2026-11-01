#if DEBUG
import Foundation
import SwiftData

/// DEV-ONLY sample data for previews, tests and `-seedSample` screenshots (PRD 12 Phase 0, AT-46).
enum Fixtures {
    @MainActor @discardableResult
    static func seed(_ ctx: ModelContext, owner: String, now: Date = .now) throws -> Business {
        let b = try ctx.createBusiness(owner: owner, BusinessInput(
            name: "Kaye Rental", phone: "+62 812 3456 7890", timeZoneID: "Asia/Makassar",
            dailyRateIDR: 250_000, depositIDR: 500_000))
        func dev(_ code: String, _ model: String, _ gb: Int, _ l: DeviceLifecycle = .enabled) throws -> RentalDevice {
            let d = try ctx.saveDevice(businessID: b.id, DeviceInput(unitCode: code, model: model, capacityGB: gb,
                                       dailyRateIDR: 250_000, depositIDR: 500_000))
            d.lifecycle = l
            return d
        }
        func cust(_ n: String, _ phone: String) -> Customer {
            let c = Customer(); c.businessID = b.id; c.fullName = n; c.phone = Phone.normalize(phone) ?? ""; ctx.insert(c); return c
        }
        func rent(_ code: String, _ c: Customer, _ d: RentalDevice, _ pickup: TimeInterval, _ ret: TimeInterval, _ s: RentalStatus) {
            let r = Rental(); r.businessID = b.id; r.code = code; r.customer = c; r.device = d
            r.pickupAt = now.addingTimeInterval(pickup); r.expectedReturnAt = now.addingTimeInterval(ret)
            r.status = s; r.dailyRateIDR = d.dailyRateIDR; r.depositIDR = d.depositIDR
            let q = Billing.quote(dailyRateIDR: d.dailyRateIDR, from: r.pickupAt, to: r.expectedReturnAt)
            r.billableUnits = q.billableUnits; r.subtotalIDR = q.subtotalIDR
            if s == .active { r.actualPickupAt = r.pickupAt }
            ctx.insert(r)
        }
        let d1 = try dev("IP-001", "iPhone 15 Pro", 256), d2 = try dev("IP-002", "iPhone 15", 128)
        _ = d2
        _ = try dev("IP-003", "iPhone 14 Pro", 256, .maintenance); _ = try dev("IP-004", "iPhone 13", 128)
        let d8 = try dev("IP-008", "iPhone 13", 128), d10 = try dev("IP-010", "iPhone 15", 128)
        let d15 = try dev("IP-015", "iPhone 14 Pro", 256)
        let h: TimeInterval = 3600, day = 24 * h
        // ponytail: offsets from `now` cross midnight near 23:00; only dev activity list is affected.
        rent("RNT-1024", cust("Andi Pratama", "0812 3456 7890"), d1, -2 * day, 2 * day, .active)
        rent("RNT-1025", cust("Sarah Putri", "0811 9988 7766"), d8, -3 * day, -3 * h, .active)
        rent("RNT-1026", cust("Made Arta", "0813 1122 3344"), d15, 2 * h, 3 * day, .reserved)
        rent("RNT-1027", cust("Dewi Lestari", "0815 5566 7788"), d10, -day, 1 * h, .active)
        // DEV-ONLY tracker points so the Map and history can be reviewed without a phone (never in release builds).
        func point(_ d: RentalDevice, _ lat: Double, _ lon: Double, ago: TimeInterval, acc: Double) {
            let p = LocationPoint()
            p.businessID = b.id; p.deviceID = d.id; p.latitude = lat; p.longitude = lon; p.accuracyM = acc
            p.measuredAt = now.addingTimeInterval(-ago); p.receivedAt = now.addingTimeInterval(-ago + 30)
            ctx.insert(p)
        }
        point(d1, -8.6500, 115.2167, ago: 120, acc: 18); point(d1, -8.6490, 115.2150, ago: 2_540, acc: 24)
        point(d1, -8.6475, 115.2140, ago: 5_280, acc: 20); point(d1, -8.6460, 115.2120, ago: 12_000, acc: 35)
        point(d15, -8.6705, 115.2126, ago: 720, acc: 20)          // aging
        point(d8, -8.6478, 115.2390, ago: 3 * 3_600, acc: 40)     // stale
        try ctx.save()
        return b
    }
}
#endif
