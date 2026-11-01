import Foundation
import SwiftData
import Testing
@testable import RentroAdmin

@MainActor
struct LocationTests {
    let now = Date(timeIntervalSince1970: 1_792_900_000)

    func inbound(_ device: RentalDevice, _ lat: Double = -8.65, ago: TimeInterval = 120, installation: UUID = UUID(), id: UUID = UUID()) -> InboundSample {
        InboundSample(deviceID: device.id, installationID: installation,
                      sample: LocationSample(id: id, latitude: lat, longitude: 115.2, horizontalAccuracyM: 12, measuredAt: now.addingTimeInterval(-ago)),
                      receivedAt: now.addingTimeInterval(-ago + 5))
    }
    func points(_ e: BookingTests.Env) throws -> [LocationPoint] { try e.ctx.fetch(FetchDescriptor<LocationPoint>()) }

    @Test func ingestStoresPointsForOwnDevicesOnly() throws {
        let e = try BookingTests.Env()
        let other = RentalDevice(); other.businessID = UUID(); other.unitCode = "IP-777"; e.ctx.insert(other)     // another business's unit
        let n = try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device), inbound(other)]), now: now)
        let pts = try points(e)
        #expect(n == 1 && pts.count == 1 && pts[0].deviceID == e.device.id && pts[0].businessID == e.business.id)
    }

    @Test func rereadingTheSameBatchIsIdempotent() throws {
        let e = try BookingTests.Env()
        let batch = InboundBatch(samples: [inbound(e.device)])
        let first = try e.ctx.ingestLocations(business: e.business, batch: batch, now: now)
        let second = try e.ctx.ingestLocations(business: e.business, batch: batch, now: now)
        let count = try points(e).count
        #expect(first == 1 && second == 0 && count == 1)
    }

    @Test func revokedInstallationsNeverLand() throws {
        let e = try BookingTests.Env()
        let bad = UUID()
        let n = try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device, installation: bad)], revokedInstallations: [bad]), now: now)
        let pts = try points(e)
        #expect(n == 0 && pts.isEmpty)
    }

    @Test func retentionPrunesOldPointsOnEveryIngest() throws {
        let e = try BookingTests.Env()
        let day: TimeInterval = 86_400
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device, ago: 6 * day)]), now: now)
        let before = try points(e).count
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device, ago: 60)]), now: now.addingTimeInterval(2 * day))
        let after = try points(e).count
        #expect(before == 1 && after == 1)                                  // the 6-day-old point is now 8 days old: gone
    }

    @Test func latestIsTheNewestMeasurementEvenIfItArrivedFirst() throws {
        let e = try BookingTests.Env()
        let newer = inbound(e.device, -8.7, ago: 60), older = inbound(e.device, -8.6, ago: 900)
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [newer]), now: now)
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [older]), now: now)     // arrives late
        let all = try points(e)
        let latest = Locations.latest(all)[e.device.id]
        #expect(latest?.sampleID == newer.sample.id && all.count == 2)
    }

    @Test func freshnessComesFromMeasurementAgeNotArrival() throws {
        let e = try BookingTests.Env()
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device, ago: 120)]), now: now)
        let p = Locations.latest(try points(e))[e.device.id]
        #expect(Locations.freshness(p, now: now) == .recent)
        #expect(Locations.freshness(p, now: now.addingTimeInterval(600)) == .aging)
        #expect(Locations.freshness(p, now: now.addingTimeInterval(3 * 3600)) == .stale)
        #expect(Locations.freshness(nil, now: now) == .neverReported)
    }

    @Test func deletingHistoryRemovesOnlyThatDevice() throws {
        let e = try BookingTests.Env()
        let second = try e.ctx.saveDevice(businessID: e.business.id, DeviceInput(unitCode: "IP-002", model: "iPhone 13"))
        try e.ctx.ingestLocations(business: e.business, batch: InboundBatch(samples: [inbound(e.device), inbound(second)]), now: now)
        try e.ctx.deleteLocationHistory(deviceID: e.device.id)
        let left = try points(e).map(\.deviceID)
        #expect(left == [second.id])
    }

    @Test func pinLabelsMatchTheFigmaPins() {
        #expect(Locations.pinLabel("IP-001") == "01" && Locations.pinLabel("IP-015") == "15" && Locations.pinLabel("IP-120") == "120")
        #expect(Locations.pinLabel("IP-7") == "7" && Locations.pinLabel("ABCDE") == "ABC")
    }

    @Test func syncSaysNotConfiguredInsteadOfInventingData() async throws {
        let e = try BookingTests.Env()
        let sync = LocationSync()
        await sync.refresh(context: e.ctx, business: e.business)
        let pts = try points(e)
        #expect(sync.state == .notConfigured && pts.isEmpty)
    }

    @Test func syncPullsThroughTheGateway() async throws {
        let e = try BookingTests.Env()
        let server = LoopbackServer(now: { now }), owner = LoopbackOwner(server: server, now: { now })
        let issued = try await owner.issuePairing(for: PairingUnit(deviceID: e.device.id, unitCode: "IP-001", businessName: "B", deviceModel: "iPhone 15"))
        let claim = try await LoopbackTransport(server: server).claim(code: issued.code, installationID: UUID())
        _ = try await server.upload([LocationSample(latitude: -8.65, longitude: 115.2, horizontalAccuracyM: 8, measuredAt: now.addingTimeInterval(-30))], credential: claim.credential)
        let sync = LocationSync(gateway: owner, now: { now })
        await sync.refresh(context: e.ctx, business: e.business)
        if case .synced = sync.state {} else { Issue.record("expected synced, got \(sync.state)") }
        let pts = try points(e)
        #expect(pts.count == 1)
    }
}
