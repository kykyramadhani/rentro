import Foundation

/// PRD 4.6 freshness; a pin's age, never "live"/"online".
enum LocationFreshness: Equatable {
    case recent, aging, stale, neverReported, permissionRequired

    init(age: TimeInterval?) {
        guard let age else { self = .neverReported; return }
        self = age <= 300 ? .recent : age <= 1800 ? .aging : .stale
    }
}
