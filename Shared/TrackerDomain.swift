import Foundation

enum OSLocationAuth: String, Codable, Sendable { case notDetermined, denied, restricted, whenInUse, always }

/// Explicit, versioned, revocable consent (PRD 4.8, T02). Never implied by pairing or by an OS prompt.
struct Consent: Codable, Equatable {
    var version: Int
    var acceptedAt: Date
    var revokedAt: Date?
    var businessName: String
    var unitCode: String
    var isActive: Bool { revokedAt == nil }
}

enum ConsentText {
    static let version = 1
    static let retentionDays = 7       // PRD 15 default; disclosed before the OS prompt
}

/// What the rented iPhone may truthfully claim about itself (PRD T03, AT-42).
enum TrackerStatus: Equatable {
    case notPaired, needsConsent, permissionRequired, paused, ended, noRecentSignal, sharing

    var title: String {
        switch self {
        case .notPaired: String(localized: "Not paired")
        case .needsConsent: String(localized: "Not tracking")
        case .permissionRequired: String(localized: "Permission required")
        case .paused: String(localized: "Paused")
        case .ended: String(localized: "Sharing ended")
        case .noRecentSignal: String(localized: "No recent signal")
        case .sharing: String(localized: "Tracking active")
        }
    }

    /// "Active" is earned: the server must have acknowledged a recent point.
    static func derive(paired: Bool, consent: Consent?, auth: OSLocationAuth, sharingEnabled: Bool,
                       sharingEndsAt: Date?, lastUploadAckAt: Date?, now: Date, staleAfter: TimeInterval = 30 * 60) -> TrackerStatus {
        guard paired else { return .notPaired }
        guard let consent, consent.isActive else { return .needsConsent }
        if let end = sharingEndsAt, now >= end { return .ended }
        guard auth == .whenInUse || auth == .always else { return .permissionRequired }
        guard sharingEnabled else { return .paused }
        guard let ack = lastUploadAckAt, now.timeIntervalSince(ack) <= staleAfter else { return .noRecentSignal }
        return .sharing
    }
}

/// "2 min ago" style ages that never round a stale point into "now".
enum Age {
    static func text(from date: Date?, now: Date) -> String {
        guard let date else { return String(localized: "Never") }
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return String(localized: "Just now")
        case ..<3600: return String(localized: "\(s / 60) min ago")
        case ..<86_400: return String(localized: "\(s / 3600) h ago")
        default: return String(localized: "\(s / 86_400) d ago")
        }
    }
}
