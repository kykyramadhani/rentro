import Foundation
import SwiftData

enum DomainError: LocalizedError, Equatable {
    case invalid(String)
    case duplicateUnitCode
    case conflict
    case overpayment

    var errorDescription: String? {
        switch self {
        case .invalid(let m): m
        case .duplicateUnitCode: String(localized: "A device with this unit code already exists.")
        case .conflict: String(localized: "This iPhone is already booked for these dates.")
        case .overpayment: String(localized: "This is more than the balance due. Confirm to record an overpayment.")
        }
    }
}

struct BusinessInput {
    var name = "", phone = "", address = ""
    var timeZoneID = TimeZone.current.identifier
    var dailyRateIDR = 0, depositIDR = 0
}

struct DeviceInput {
    var unitCode = "", model = "", color = "", serial = ""
    var capacityGB = 128
    var dailyRateIDR = 0, depositIDR = 0
    var isActive = true
}

extension ModelContext {
    @discardableResult
    func createBusiness(owner: String, _ i: BusinessInput) throws -> Business {
        let name = i.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.invalid(String(localized: "Enter your business name.")) }
        guard TimeZone(identifier: i.timeZoneID) != nil else { throw DomainError.invalid(String(localized: "Choose a valid timezone.")) }
        guard i.dailyRateIDR >= 0, i.depositIDR >= 0 else { throw DomainError.invalid(String(localized: "Rates cannot be negative.")) }
        let b = Business()
        b.ownerAppleID = owner
        b.name = name
        b.phone = i.phone.trimmingCharacters(in: .whitespaces)
        b.address = i.address.trimmingCharacters(in: .whitespaces)
        b.timeZoneID = i.timeZoneID
        b.defaultDailyRateIDR = i.dailyRateIDR
        b.defaultDepositIDR = i.depositIDR
        insert(b)
        try save()
        return b
    }

    /// Add (`device == nil`) or edit. Unit code is unique per business, case-insensitive.
    @discardableResult
    func saveDevice(_ device: RentalDevice? = nil, businessID: UUID, _ i: DeviceInput) throws -> RentalDevice {
        let code = i.unitCode.trimmingCharacters(in: .whitespaces).uppercased()
        let model = i.model.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { throw DomainError.invalid(String(localized: "Enter a unit code.")) }
        guard !model.isEmpty else { throw DomainError.invalid(String(localized: "Enter the device model.")) }
        guard i.dailyRateIDR >= 0, i.depositIDR >= 0 else { throw DomainError.invalid(String(localized: "Rates cannot be negative.")) }
        let existing = try fetch(FetchDescriptor<RentalDevice>(predicate: #Predicate { $0.businessID == businessID && $0.unitCode == code }))
        if existing.contains(where: { $0.id != device?.id }) { throw DomainError.duplicateUnitCode }

        let d = device ?? RentalDevice()
        if device == nil { d.businessID = businessID; insert(d) }
        d.unitCode = code
        d.model = model
        d.capacityGB = i.capacityGB
        d.color = i.color.trimmingCharacters(in: .whitespaces)
        d.serial = i.serial.trimmingCharacters(in: .whitespaces)
        d.dailyRateIDR = i.dailyRateIDR
        d.depositIDR = i.depositIDR
        if d.lifecycle != .maintenance { d.lifecycle = i.isActive ? .enabled : .retired }
        try save()
        return d
    }
}

/// Indonesian phone numbers stored as +62… (PRD S23).
enum Phone {
    static func normalize(_ raw: String) -> String? {
        var d = raw.filter(\.isNumber)
        guard !d.isEmpty else { return nil }
        if d.hasPrefix("62") { d.removeFirst(2) } else if d.hasPrefix("0") { d.removeFirst() }
        guard (8...13).contains(d.count), !d.hasPrefix("0") else { return nil }
        return "+62" + d
    }

    /// "+6281234567890" → "+62 812 3456 7890"
    static func display(_ n: String) -> String {
        guard n.hasPrefix("+62") else { return n }
        let d = Array(n.dropFirst(3))
        let parts = [d.prefix(3), d.dropFirst(3).prefix(4), d.dropFirst(7)].map { String($0) }.filter { !$0.isEmpty }
        return "+62 " + parts.joined(separator: " ")
    }
}

extension ModelContext {
    @discardableResult
    func saveCustomer(_ customer: Customer? = nil, businessID: UUID, name: String, phone: String) throws -> Customer {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.invalid(String(localized: "Enter the customer's name.")) }
        guard name.count <= 80 else { throw DomainError.invalid(String(localized: "The name is too long.")) }
        let raw = phone.trimmingCharacters(in: .whitespaces)
        var normalized = ""
        if !raw.isEmpty {
            guard let n = Phone.normalize(raw) else { throw DomainError.invalid(String(localized: "Enter a valid Indonesian phone number.")) }
            normalized = n
        }
        let c = customer ?? Customer()
        if customer == nil { c.businessID = businessID; insert(c) }
        c.fullName = name
        c.phone = normalized
        try save()
        return c
    }
}

extension ModelContext {
    /// S17. Maintenance/retire cannot silently invalidate open bookings: resolve them first (PRD S17).
    func setDeviceStatus(_ d: RentalDevice, _ status: DeviceLifecycle, note: String = "", now: Date = .now) throws {
        if status != .enabled {
            let open = (d.rentals ?? []).filter { $0.status == .reserved || $0.status == .active }
            guard open.isEmpty else {
                let codes = open.map(\.code).sorted().joined(separator: ", ")
                throw DomainError.invalid(open.count == 1
                    ? String(localized: "This iPhone has an open rental (\(codes)). Return or cancel it first.")
                    : String(localized: "This iPhone has \(open.count) open rentals (\(codes)). Return or cancel them first."))
            }
        }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status != .maintenance || !note.isEmpty else { throw DomainError.invalid(String(localized: "Describe the issue.")) }
        d.lifecycle = status
        d.maintenanceNote = status == .maintenance ? note : ""
        d.maintenanceSince = status == .maintenance ? now : nil
        try save()
    }
}
