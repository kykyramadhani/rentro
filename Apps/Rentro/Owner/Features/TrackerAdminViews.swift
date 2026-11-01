import CoreImage.CIFilterBuiltins
import MapKit
import SwiftData
import SwiftUI

/// "Location tracking" card on Device Detail. Figma 43:955 / 43:1431.
struct LocationCard: View {
    let point: LocationPoint
    let now: Date
    var body: some View {
        let f = Locations.freshness(point, now: now), c = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        HStack(alignment: .top, spacing: Space.s16) {
            Map(initialPosition: .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))), interactionModes: []) {
                Marker("", coordinate: c).tint(Color.brandSolid)
            }
            .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: Radius.r12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                FreshnessBadge(freshness: f)
                Text("Last reported \(Age.text(from: point.measuredAt, now: now))").font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Text("Accuracy ±\(Int(point.accuracyM)) m").font(.caption).foregroundStyle(Color.textSecondary)
                if f == .stale { Text("May no longer be current.").font(.caption).foregroundStyle(Color.textSecondary) }
            }
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("rentro.device.location")
    }
}

/// S20 Location History. Figma 45:704 / 45:1045. Retention-limited, never interpreted as movement.
struct LocationHistoryView: View {
    @Environment(\.modelContext) private var context
    let device: RentalDevice
    let business: Business
    @Query private var points: [LocationPoint]
    @State private var confirmDelete = false
    @State private var error: String?

    init(device: RentalDevice, business: Business) {
        self.device = device
        self.business = business
        let id = device.id
        _points = Query(filter: #Predicate<LocationPoint> { $0.deviceID == id }, sort: \.measuredAt, order: .reverse)
    }

    var body: some View {
        let tz = business.timeZone, now = Date.now
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                Text("Retention-limited tracker events. Kept for \(ConsentText.retentionDays) days, then deleted.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                if points.isEmpty {
                    EmptyState(title: "No history", message: "Reported points appear here and are deleted after \(ConsentText.retentionDays) days.", symbol: "clock")
                }
                ForEach(points) { p in
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Text(label(p.measuredAt, tz, now)).font(.headline).foregroundStyle(Color.textPrimary)
                        Text("±\(Int(p.accuracyM)) m · received \(p.receivedAt.clock(tz))").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    .card().accessibilityElement(children: .combine)
                }
                if !points.isEmpty {
                    Text("No movement is inferred between reported points.").font(.caption).foregroundStyle(Color.textSecondary).padding(.top, Space.s8)
                    Button("Delete history", role: .destructive) { confirmDelete = true }
                        .frame(minHeight: 44).accessibilityIdentifier("rentro.history.delete")
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Location History").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete location history for \(device.unitCode)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) {
                do { try context.deleteLocationHistory(deviceID: device.id) } catch { self.error = error.localizedDescription }
            }
        } message: { Text("This removes every stored point for this iPhone. It cannot be undone.") }
    }

    private func label(_ d: Date, _ tz: TimeZone, _ now: Date) -> String {
        var cal = Calendar.current; cal.timeZone = tz
        return cal.isDate(d, inSameDayAs: now) ? String(localized: "Today · \(d.clock(tz))") : d.stamp(tz, now: now)
    }
}

/// Pair Tracker (admin side of T01). One-minute codes: the sheet shows a countdown and makes a new code cheap.
struct PairTrackerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationSync.self) private var sync
    let device: RentalDevice
    let business: Business
    @State private var issued: IssuedCode?
    @State private var error: TransportError?
    @State private var working = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s16) {
                Text("Open Rentro Tracker on the rental iPhone and scan this code, or type it in.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                if let issued { codeCard(issued) }
                else if let error { problem(error) }
                else { ProgressView().frame(height: 200) }
                Spacer()
                Button(issued == nil ? "Try again" : "New code") { Task { await issue() } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(working || error == .notConfigured)
                    .accessibilityIdentifier("rentro.pair.new")
            }
            .padding(Space.s20)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle("Pair \(device.unitCode)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await issue() }
        }
    }

    private func codeCard(_ c: IssuedCode) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(c.expiresAt.timeIntervalSince(ctx.date).rounded(.up))), expired = left == 0
            VStack(spacing: Space.s12) {
                if let img = Self.qr(PairingCode.qrPayload(c.code)) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(width: 180, height: 180)
                        .padding(Space.s12).background(.white, in: RoundedRectangle(cornerRadius: Radius.r12))
                        .opacity(expired ? 0.15 : 1).accessibilityLabel("Pairing QR code for \(device.unitCode)")
                }
                Text(PairingCode.display(c.code)).font(.title2.monospaced().weight(.semibold)).foregroundStyle(Color.textPrimary)
                    .opacity(expired ? 0.3 : 1).accessibilityIdentifier("rentro.pair.code")
                Text(expired ? "Code expired" : "Expires in \(left) s").font(.footnote.weight(.semibold))
                    .foregroundStyle(expired ? Color.textDanger : Color.textSecondary).accessibilityIdentifier("rentro.pair.countdown")
            }
            .frame(maxWidth: .infinity).card()
        }
    }

    private func problem(_ e: TransportError) -> some View {
        VStack(spacing: Space.s8) {
            Image(systemName: "icloud.slash").font(.largeTitle).foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            Text(e == .notConfigured ? "Pairing needs iCloud setup" : "Couldn't make a code").font(.headline).foregroundStyle(Color.textPrimary)
            Text(e == .notConfigured ? "Trackers connect through iCloud. This build isn't connected yet, so no code can be issued." : e.userMessage)
                .font(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).card().accessibilityIdentifier("rentro.pair.error")
    }

    private func issue() async {
        working = true; error = nil; issued = nil
        defer { working = false }
        do {
            issued = try await sync.gateway.issuePairing(for: PairingUnit(deviceID: device.id, unitCode: device.unitCode,
                                                                          businessName: business.name, deviceModel: device.model))
        } catch let e as TransportError { error = e } catch { self.error = .offline }
    }

    static func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
