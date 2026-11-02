import Foundation
import SwiftData


/// Persisted lifecycle. `overdue` is derived, never stored (PRD 4.2).
enum RentalStatus: String, Codable { case reserved, active, completed, cancelled }
enum DeviceLifecycle: String, Codable { case enabled, maintenance, retired }
/// Late fee is charged per started day or per started hour past expected return, after grace (PRD S30).
enum LateFeeUnit: String, CaseIterable, Codable {
    case day, hour
    var title: String { self == .day ? String(localized: "per day") : String(localized: "per hour") }
}

// Every stored property has a default and no `.unique`, so the schema stays CloudKit-compatible (PRD 8.4).
// Uniqueness (unit code) is enforced in the domain layer, see Services.swift.

@Model final class Business {
    var id = UUID()
    var ownerAppleID = ""
    var name = ""
    var phone = ""
    var address = ""
    var wilayahKode = ""      // village kode (Kepmendagri), "" when not set; see WilayahPicker
    var timeZoneID = "Asia/Makassar"
    var currencyCode = "IDR"
    var defaultDailyRateIDR = 0
    var defaultDepositIDR = 0
    var lateGraceMinutes = 0
    var lateFeeUnitRaw = LateFeeUnit.day.rawValue
    var lateFeeAmountIDR = 0     // 0 = the device's own rate: one day's rate per day, or a 24th of it per hour
    var turnaroundMinutes = 0
    var createdAt = Date.now

    init() {}

    var lateFeeUnit: LateFeeUnit {
        get { LateFeeUnit(rawValue: lateFeeUnitRaw) ?? .day }
        set { lateFeeUnitRaw = newValue.rawValue }
    }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var calendar: Calendar { var c = Calendar.current; c.timeZone = timeZone; return c }
}

@Model final class RentalDevice {
    var id = UUID()
    var businessID = UUID()
    var unitCode = ""
    var model = ""
    var capacityGB = 128
    var color = ""
    var serial = ""          // sensitive (PRD 4.8); never shown in lists
    var dailyRateIDR = 0
    var depositIDR = 0
    var lifecycleRaw = DeviceLifecycle.enabled.rawValue
    var maintenanceNote = ""
    var maintenanceSince: Date?
    var createdAt = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Rental.device) var rentals: [Rental]? = []

    init() {}

    var lifecycle: DeviceLifecycle {
        get { DeviceLifecycle(rawValue: lifecycleRaw) ?? .enabled }
        set { lifecycleRaw = newValue.rawValue }
    }
}

@Model final class Customer {
    var id = UUID()
    var businessID = UUID()
    var fullName = ""
    var phone = ""
    var createdAt = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Rental.customer) var rentals: [Rental]? = []

    init() {}
}

@Model final class Rental {
    var id = UUID()
    var businessID = UUID()
    var code = ""             // RNT-1024
    var customer: Customer?
    var device: RentalDevice?
    var statusRaw = RentalStatus.reserved.rawValue
    var pickupAt = Date.now
    var expectedReturnAt = Date.now
    var actualPickupAt: Date?
    var actualReturnAt: Date?
    var dailyRateIDR = 0      // snapshot at booking (PRD 4.1)
    var depositIDR = 0        // deposit required; a held liability, never income (PRD 4.4)
    var lateGraceMinutes = 0  // late-fee policy snapshot, like the rate (PRD 4.1)
    var lateFeeUnitRaw = LateFeeUnit.day.rawValue
    var lateFeeAmountIDR = 0
    var billableUnits = 1
    var subtotalIDR = 0       // billableUnits * dailyRateIDR
    var discountIDR = 0
    var lateFeeIDR = 0
    var damageFeeIDR = 0
    var cancelReason = ""
    var idempotencyKey = ""
    var createdAt = Date.now
    @Relationship(deleteRule: .cascade, inverse: \PaymentEntry.rental) var payments: [PaymentEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \RentalEvent.rental) var events: [RentalEvent]? = []

    init() {}

    var status: RentalStatus {
        get { RentalStatus(rawValue: statusRaw) ?? .reserved }
        set { statusRaw = newValue.rawValue }
    }
    /// totalCharges = subtotal - discount + late + damage (PRD 4.4). Deposit excluded.
    var totalChargesIDR: Int { subtotalIDR - discountIDR + lateFeeIDR + damageFeeIDR }
    var amountPaidIDR: Int { (payments ?? []).filter { $0.category == .rentalPayment || $0.category == .adjustment }.reduce(0) { $0 + $1.amountIDR } }
    var balanceDueIDR: Int { totalChargesIDR - amountPaidIDR }
    var paymentState: PaymentState {
        let due = balanceDueIDR
        return due < 0 ? .overpaid : due == 0 ? .paid : amountPaidIDR > 0 ? .partial : .unpaid
    }
    /// Deposit currently held as liability = received - refunded - deducted.
    var depositHeldIDR: Int {
        (payments ?? []).reduce(0) { sum, p in
            switch p.category {
            case .depositReceived: sum + p.amountIDR
            case .depositRefunded, .depositDeduction: sum - p.amountIDR
            default: sum
            }
        }
    }
    var lateFeeUnit: LateFeeUnit { LateFeeUnit(rawValue: lateFeeUnitRaw) ?? .day }
    var customerName: String { customer?.fullName ?? String(localized: "Unknown customer") }
    var unitCode: String { device?.unitCode ?? "-" }
    var deviceModel: String { device?.model ?? String(localized: "Removed device") }

    func badge(now: Date, calendar: Calendar) -> RentalBadge {
        switch status {
        case .reserved: .upcoming
        case .completed: .returned
        case .cancelled: .cancelled
        case .active:
            if now > expectedReturnAt { .overdue }
            else if calendar.isDate(expectedReturnAt, inSameDayAs: now) { .dueToday }
            else { .active }
        }
    }
}

enum PaymentState: String { case unpaid, partial, paid, overpaid }
enum PaymentMethod: String, CaseIterable, Codable {
    case cash, bankTransfer = "bank_transfer", eWallet = "e_wallet", other
    var title: String {
        switch self { case .cash: String(localized: "Cash"); case .bankTransfer: String(localized: "Bank transfer"); case .eWallet: String(localized: "E-wallet"); case .other: String(localized: "Other") }
    }
}
/// PRD 4.5 ledger categories. Amounts are stored positive; the category gives the direction.
enum PaymentCategory: String, Codable { case rentalPayment, depositReceived, depositRefunded, depositDeduction, adjustment }

/// Append-only: corrections are new entries, never edits or deletes (PRD 8.2.6).
@Model final class PaymentEntry {
    var id = UUID()
    var businessID = UUID()
    var rental: Rental?
    var categoryRaw = PaymentCategory.rentalPayment.rawValue
    var amountIDR = 0
    var methodRaw = PaymentMethod.cash.rawValue
    var reference = ""        // note / transfer reference / deduction reason
    var paidAt = Date.now
    var idempotencyKey = ""
    var createdAt = Date.now

    init() {}

    var category: PaymentCategory {
        get { PaymentCategory(rawValue: categoryRaw) ?? .rentalPayment }
        set { categoryRaw = newValue.rawValue }
    }
    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
}

/// Append-only operational audit trail (PRD 8.1).
@Model final class RentalEvent {
    var id = UUID()
    var businessID = UUID()
    var rental: Rental?
    var type = ""             // created, pickup, extended, returned, cancelled
    var note = ""
    var createdAt = Date.now

    init() {}

    /// What the timeline shows; `type` stays a stable key in the data.
    var title: String {
        switch type {
        case "created": String(localized: "Created")
        case "pickup": String(localized: "Pickup")
        case "extended": String(localized: "Extended")
        case "returned": String(localized: "Returned")
        case "cancelled": String(localized: "Cancelled")
        default: type.capitalized
        }
    }
}

/// Only the read-state is stored; alerts themselves are derived so they can never go stale or duplicate (PRD 4.7).
@Model final class AlertRecord {
    var id = UUID()
    var businessID = UUID()
    var key = ""              // dedupe key, e.g. "overdue.<rentalID>"
    var readAt: Date?

    init() {}
}

enum RentroSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Business.self, RentalDevice.self, Customer.self, Rental.self, LocationPoint.self, PaymentEntry.self, RentalEvent.self, AlertRecord.self] }
}

/// Add a new `RentroSchemaV2` + stage here before any breaking model change (PRD 8.2.8).
enum RentroMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RentroSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum RentalBadge: Equatable {
    case upcoming, active, dueToday, overdue, returned, cancelled

    var title: String {
        switch self {
        case .upcoming: String(localized: "Upcoming")
        case .active: String(localized: "Active")
        case .dueToday: String(localized: "Due today")
        case .overdue: String(localized: "Overdue")
        case .returned: String(localized: "Returned")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}

enum DeviceStatus: Equatable {
    case available, rented, maintenance
    var title: String {
        switch self { case .available: String(localized: "Available"); case .rented: String(localized: "Rented"); case .maintenance: String(localized: "Maintenance") }
    }
}


struct DashboardSummary: Equatable {
    var totalUnits = 0, rented = 0, available = 0, overdue = 0
}

enum Activity {
    case pickup(Rental), `return`(Rental), overdue(Rental)
}

enum RentalFilter: CaseIterable { case all, active, upcoming, overdue }
enum DeviceFilter: CaseIterable { case all, available, rented }

/// Pure derivations shared by Home / Rentals / Devices.
enum Derive {
    static func status(of device: RentalDevice, rentals: [Rental]) -> DeviceStatus {
        if device.lifecycle != .enabled { return .maintenance }
        return rentals.contains { $0.device?.id == device.id && $0.status == .active } ? .rented : .available
    }

    static func summary(devices: [RentalDevice], rentals: [Rental], now: Date, calendar: Calendar) -> DashboardSummary {
        let enabled = devices.filter { $0.lifecycle == .enabled }
        let statuses = enabled.map { status(of: $0, rentals: rentals) }
        return DashboardSummary(
            totalUnits: enabled.count,
            rented: statuses.filter { $0 == .rented }.count,
            available: statuses.filter { $0 == .available }.count,
            overdue: rentals.filter { $0.badge(now: now, calendar: calendar) == .overdue }.count
        )
    }

    /// Today's pickups and returns (business timezone via `calendar`), then overdue.
    static func activity(rentals: [Rental], now: Date, calendar: Calendar) -> [Activity] {
        let pickups = rentals.filter { $0.status == .reserved && calendar.isDate($0.pickupAt, inSameDayAs: now) }
            .sorted { $0.pickupAt < $1.pickupAt }.map(Activity.pickup)
        let returns = rentals.filter { $0.badge(now: now, calendar: calendar) == .dueToday }
            .sorted { $0.expectedReturnAt < $1.expectedReturnAt }.map(Activity.return)
        let overdue = rentals.filter { $0.badge(now: now, calendar: calendar) == .overdue }.map(Activity.overdue)
        return pickups + returns + overdue
    }

    static func rentals(_ all: [Rental], filter: RentalFilter, query: String, now: Date, calendar: Calendar) -> [Rental] {
        all.filter { r in
            let b = r.badge(now: now, calendar: calendar)
            switch filter {
            case .all: break
            case .active: if r.status != .active { return false }   // includes overdue (PRD S04)
            case .upcoming: if b != .upcoming { return false }
            case .overdue: if b != .overdue { return false }
            }
            return matches(query, r.customerName, r.code, r.unitCode, r.deviceModel)
        }
    }

    static func devices(_ all: [RentalDevice], rentals: [Rental], filter: DeviceFilter, query: String) -> [RentalDevice] {
        all.filter { d in
            let s = status(of: d, rentals: rentals)
            switch filter {
            case .all: break
            case .available: if s != .available { return false }
            case .rented: if s != .rented { return false }
            }
            return matches(query, d.model, d.unitCode)
        }
    }

    private static func matches(_ query: String, _ fields: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}
