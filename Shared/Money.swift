import Foundation

/// Exact whole-rupiah amount (PRD 4.1: never floating point).
struct Money: Equatable, Codable {
    var idr: Int64

    /// "Rp 250.000": fixed id-ID grouping, independent of device locale.
    var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return "Rp " + (f.string(from: NSNumber(value: idr)) ?? "\(idr)")
    }
}
