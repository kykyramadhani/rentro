import Foundation
import Observation
import SwiftData

/// One accepted tracker point. History is bounded to the disclosed retention; "latest" per device is derived, never stored.
@Model final class LocationPoint {
    var id = UUID()
    var businessID = UUID()
    var deviceID = UUID()
    var sampleID = UUID()            // the tracker's upload_event_id: dedupes re-reads
    var installationID = UUID()
    var latitude = 0.0
    var longitude = 0.0
    var accuracyM = 0.0
    var measuredAt = Date.now
    var receivedAt = Date.now

    init() {}
}

enum Locations {
    /// Newest point per device, by when it was measured (a late, older upload never replaces it: AT-18).
    static func latest(_ points: [LocationPoint]) -> [UUID: LocationPoint] {
        points.reduce(into: [:]) { acc, p in
            if let cur = acc[p.deviceID], cur.measuredAt >= p.measuredAt { return }
            acc[p.deviceID] = p
        }
    }
    static func freshness(_ p: LocationPoint?, now: Date) -> LocationFreshness {
        LocationFreshness(age: p.map { now.timeIntervalSince($0.measuredAt) })
    }
    /// "01" for IP-001, "15" for IP-015: the trailing number, as on the Figma pins.
    static func pinLabel(_ unitCode: String) -> String {
        var digits = String(unitCode.reversed().prefix { $0.isNumber }.reversed())
        if digits.isEmpty { return String(unitCode.prefix(3)) }
        while digits.count > 2, digits.first == "0" { digits.removeFirst() }
        return digits
    }
}

extension ModelContext {
    /// Applies the reader rules (PRD 8.1) to what trackers uploaded. Only this business's own devices can land here.
    @discardableResult
    func ingestLocations(business: Business, batch: InboundBatch, now: Date = .now) throws -> Int {
        let bid = business.id
        let own = Set(try fetch(FetchDescriptor<RentalDevice>(predicate: #Predicate { $0.businessID == bid })).map(\.id))
        let known = Set(try fetch(FetchDescriptor<LocationPoint>(predicate: #Predicate { $0.businessID == bid })).map(\.sampleID))
        let accepted = LocationAggregator.accept(batch.samples.filter { own.contains($0.deviceID) },
                                                 revoked: batch.revokedInstallations, knownSampleIDs: known, now: now)
        for i in accepted {
            let p = LocationPoint()
            p.businessID = bid; p.deviceID = i.deviceID; p.sampleID = i.sample.id; p.installationID = i.installationID
            p.latitude = i.sample.latitude; p.longitude = i.sample.longitude; p.accuracyM = i.sample.horizontalAccuracyM
            p.measuredAt = i.sample.measuredAt; p.receivedAt = i.receivedAt
            insert(p)
        }
        try pruneLocations(businessID: bid, now: now)
        try save()
        return accepted.count
    }

    /// Nothing older than the disclosed retention is kept (PRD S20).
    func pruneLocations(businessID: UUID, now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-LocationAggregator.retention)
        for p in try fetch(FetchDescriptor<LocationPoint>(predicate: #Predicate { $0.businessID == businessID && $0.measuredAt < cutoff })) { delete(p) }
    }

    func deleteLocationHistory(deviceID: UUID) throws {
        for p in try fetch(FetchDescriptor<LocationPoint>(predicate: #Predicate { $0.deviceID == deviceID })) { delete(p) }
        try save()
    }
}

/// Pulls tracker uploads through the owner gateway. Never invents a point: with no backend it says so.
@MainActor @Observable
final class LocationSync {
    enum State: Equatable { case idle, syncing, notConfigured, failed(String), synced(Date) }
    private(set) var state: State = .idle
    let gateway: OwnerGateway
    private let now: () -> Date

    init(gateway: OwnerGateway = UnconfiguredOwnerGateway(), now: @escaping () -> Date = { .now }) { self.gateway = gateway; self.now = now }

    func refresh(context: ModelContext, business: Business) async {
        guard state != .syncing else { return }
        state = .syncing
        do {
            let batch = try await gateway.inbound()
            try context.ingestLocations(business: business, batch: batch, now: now())
            state = .synced(now())
        } catch TransportError.notConfigured {
            state = .notConfigured
        } catch let e as TransportError {
            state = .failed(e.userMessage)
        } catch { state = .failed(error.localizedDescription) }
    }
}
