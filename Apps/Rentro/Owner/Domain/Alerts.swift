import Foundation
import SwiftData
import UserNotifications

enum AlertKind: String, CaseIterable {
    case overdue, dueToday, pendingPickup, paymentDue
    var shortTitle: String {
        switch self { case .overdue: String(localized: "Overdue"); case .dueToday: String(localized: "Due today"); case .pendingPickup: String(localized: "Pickup"); case .paymentDue: String(localized: "Payment") }
    }
    var title: String {
        switch self {
        case .overdue: String(localized: "Overdue rental")
        case .dueToday: String(localized: "Return due today")
        case .pendingPickup: String(localized: "Pickup today")
        case .paymentDue: String(localized: "Payment due")
        }
    }
}

struct AppAlert: Identifiable {
    let kind: AlertKind
    let rental: Rental
    var key: String { "\(kind.rawValue).\(rental.id.uuidString)" }   // one alert per rental+kind: no duplicates (AT-06)
    var id: String { key }
}

enum Alerts {
    /// Derived at render time from current state, most urgent first (PRD S27).
    static func derive(rentals: [Rental], now: Date, calendar: Calendar) -> [AppAlert] {
        var out: [AppAlert] = []
        for r in rentals {
            switch r.badge(now: now, calendar: calendar) {
            case .overdue: out.append(AppAlert(kind: .overdue, rental: r))
            case .dueToday: out.append(AppAlert(kind: .dueToday, rental: r))
            case .upcoming where r.pickupAt <= now || calendar.isDate(r.pickupAt, inSameDayAs: now):
                out.append(AppAlert(kind: .pendingPickup, rental: r))
            case .returned where r.balanceDueIDR > 0: out.append(AppAlert(kind: .paymentDue, rental: r))
            default: break
            }
        }
        let order: [AlertKind] = [.overdue, .dueToday, .pendingPickup, .paymentDue]
        return out.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }

    static func detail(_ a: AppAlert, now: Date, timeZone: TimeZone) -> String {
        let r = a.rental
        switch a.kind {
        case .overdue: return String(localized: "\(r.code) · \(duration(now.timeIntervalSince(r.expectedReturnAt))) overdue")
        case .dueToday: return String(localized: "\(r.code) · \(r.expectedReturnAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))")
        case .pendingPickup: return String(localized: "\(r.code) · \(r.pickupAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))")
        case .paymentDue: return String(localized: "\(r.code) · \(r.balanceDueIDR.rupiah)")
        }
    }

    private static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m >= 1440 ? String(localized: "\(m / 1440)d") : m >= 60 ? String(localized: "\(m / 60)h") : String(localized: "\(max(m, 1))m")
    }
}

extension ModelContext {
    func markRead(_ keys: [String], businessID: UUID, at: Date = .now) throws {
        let existing = Set(try fetch(FetchDescriptor<AlertRecord>(predicate: #Predicate { $0.businessID == businessID })).map(\.key))
        for k in keys where !existing.contains(k) {
            let rec = AlertRecord(); rec.businessID = businessID; rec.key = k; rec.readAt = at; insert(rec)
        }
        try save()
    }
}

// MARK: local reminders (PRD 4.7: deterministic, local, no server needed)

struct ReminderPrefs: Equatable {
    var pickup = true, returned = true, overdue = true
    var pickupLeadMinutes = 24 * 60     // PRD default 24h
    var returnLeadMinutes = 120         // PRD default 2h
}

struct PlannedReminder: Equatable {
    let id: String
    let fireAt: Date
    let title: String
    let body: String
}

enum Reminders {
    static let idPrefix = "rentro."
    /// iOS keeps at most 64 pending local notifications.
    // ponytail: soonest 60 only; a business with more upcoming rentals than that re-plans as time passes.
    static let maxPending = 60

    /// Future reminders only; ids are per rental+kind, so re-planning replaces instead of duplicating.
    static func plan(rentals: [Rental], prefs: ReminderPrefs, now: Date) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        for r in rentals {
            switch r.status {
            case .reserved where prefs.pickup:
                out.append(.init(id: "\(idPrefix)pickup.\(r.id)", fireAt: r.pickupAt.addingTimeInterval(-Double(prefs.pickupLeadMinutes) * 60),
                                 title: String(localized: "Pickup coming up"), body: "\(r.code) · \(r.customerName) · \(r.deviceModel)"))
            case .active:
                if prefs.returned {
                    out.append(.init(id: "\(idPrefix)return.\(r.id)", fireAt: r.expectedReturnAt.addingTimeInterval(-Double(prefs.returnLeadMinutes) * 60),
                                     title: String(localized: "Return due soon"), body: "\(r.code) · \(r.customerName) · \(r.deviceModel)"))
                }
                if prefs.overdue {
                    out.append(.init(id: "\(idPrefix)overdue.\(r.id)", fireAt: r.expectedReturnAt,
                                     title: String(localized: "Rental overdue"), body: String(localized: "\(r.code) · \(r.customerName) was due back now")))
                }
            default: break
            }
        }
        return Array(out.filter { $0.fireAt > now }.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
    }

    /// Replace every pending Rentro reminder with `plan`. Does nothing unless notifications are already allowed.
    @MainActor static func sync(_ plan: [PlannedReminder]) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for p in plan {
            let c = UNMutableNotificationContent()
            c.title = p.title; c.body = p.body; c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(p.fireAt.timeIntervalSinceNow, 1), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: c, trigger: trigger))
        }
    }
}
