import Foundation

struct LocationSample: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()                  // upload_event_id: dedupes retries
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyM: Double
    var measuredAt: Date
}

enum SampleCheck: Equatable { case valid, invalid(String) }

enum SampleValidator {
    static let maxAccuracyM = 1000.0                 // wider fixes are noise, not a position
    static let futureTolerance: TimeInterval = 5 * 60

    static func check(_ s: LocationSample, now: Date) -> SampleCheck {
        guard s.latitude.isFinite, s.longitude.isFinite, (-90...90).contains(s.latitude), (-180...180).contains(s.longitude) else {
            return .invalid("coordinates out of range")
        }
        guard s.horizontalAccuracyM >= 0, s.horizontalAccuracyM <= maxAccuracyM else { return .invalid("unusable accuracy") }
        guard s.measuredAt <= now.addingTimeInterval(futureTolerance) else { return .invalid("timestamp in the future") }
        return .valid
    }
}

enum Geo {
    /// Haversine, metres.
    static func distance(_ a: LocationSample, _ b: LocationSample) -> Double {
        let r = 6_371_000.0, p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dp = (b.latitude - a.latitude) * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

/// Battery-aware sampling (PRD T06): record on meaningful movement or after a quiet interval, never on a fixed telemetry beat.
struct SamplingPolicy {
    var minDistanceM = 50.0
    var maxQuietInterval: TimeInterval = 5 * 60

    func shouldRecord(previous: LocationSample?, candidate: LocationSample) -> Bool {
        guard let p = previous else { return true }
        if candidate.measuredAt <= p.measuredAt { return false }        // out of order or duplicate
        return Geo.distance(p, candidate) >= minDistanceM || candidate.measuredAt.timeIntervalSince(p.measuredAt) >= maxQuietInterval
    }
}

/// Bounded offline queue (PRD T06): capped, expiring, deduplicated; oldest points go first when full.
struct UploadQueue: Codable, Equatable {
    var samples: [LocationSample] = []
    var maxCount = 200
    var maxAge: TimeInterval = 24 * 3600

    mutating func enqueue(_ s: LocationSample, now: Date) {
        guard !samples.contains(where: { $0.id == s.id }) else { return }
        samples.append(s)
        prune(now: now)
    }
    mutating func prune(now: Date) {
        samples.removeAll { now.timeIntervalSince($0.measuredAt) > maxAge }
        if samples.count > maxCount { samples.removeFirst(samples.count - maxCount) }
    }
    func nextBatch(_ n: Int = 50) -> [LocationSample] { Array(samples.prefix(n)) }
    mutating func acknowledge(_ ids: [UUID]) { let done = Set(ids); samples.removeAll { done.contains($0.id) } }
    mutating func wipe() { samples.removeAll() }
}

enum Backoff {
    /// 5s, 10s, 20s ... capped at 15 minutes.
    static func delay(attempt: Int) -> TimeInterval { min(5 * pow(2, Double(max(0, attempt))), 900) }
}
