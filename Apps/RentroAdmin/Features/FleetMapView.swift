import MapKit
import SwiftData
import SwiftUI

extension LocationFreshness {
    var title: String {
        switch self {
        case .recent: String(localized: "Location recent")
        case .aging: String(localized: "Location aging")
        case .stale: String(localized: "May no longer be current")
        case .neverReported: String(localized: "No location received")
        case .permissionRequired: String(localized: "Location permission required")
        }
    }
    var tint: Color {
        switch self { case .recent: .textSuccess; case .aging: .textWarning; case .stale, .neverReported, .permissionRequired: .textSecondary }
    }
    var pinOpacity: Double { self == .recent ? 1 : self == .aging ? 0.85 : 0.5 }   // stale markers are dimmed (PRD 4.6)
}

/// Dot + words, never colour alone. "Last reported", never "live" or "online".
struct FreshnessBadge: View {
    let freshness: LocationFreshness
    var body: some View {
        HStack(spacing: Space.s8) {
            Circle().fill(freshness.tint).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(freshness.title).font(.footnote.weight(.semibold)).foregroundStyle(freshness.tint)
        }
    }
}

/// S18 Fleet Map + S19 device sheet. Figma 43:883 / 43:1358. Only real, consented, reported points are drawn.
struct FleetMapView: View {
    let business: Business
    @Environment(AppStore.self) private var store
    @Environment(LocationSync.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var rentals: [Rental]
    @Query private var devices: [RentalDevice]
    @Query private var points: [LocationPoint]
    @State private var selected: UUID?
    @State private var query = ""
    @State private var showList = false
    @State private var position: MapCameraPosition = .automatic

    init(business: Business) {
        self.business = business
        let id = business.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
        _devices = Query(filter: #Predicate<RentalDevice> { $0.businessID == id }, sort: \.unitCode)
        _points = Query(filter: #Predicate<LocationPoint> { $0.businessID == id })
    }

    var body: some View {
        let now = Date.now
        let latest = Locations.latest(points)
        let shown = devices.filter { query.isEmpty || $0.unitCode.localizedCaseInsensitiveContains(query) || $0.model.localizedCaseInsensitiveContains(query) }
        NavigationStack {
            Group {
                if showList { list(shown, latest, now) } else { map(shown, latest, now) }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header(Derive.summary(devices: devices, rentals: rentals, now: now, calendar: business.calendar)) }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomCard(latest, now) }
            .background(Color.bgCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RentalDevice.self) { DeviceDetailView(device: $0, business: business) }
        }
        .task { await sync.refresh(context: context, business: business) }
        .onAppear(perform: focusRequested)
        .onChange(of: store.mapFocus) { _, _ in focusRequested() }
    }

    // MARK: pieces

    private func header(_ s: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Fleet Map").font(.title.bold()).foregroundStyle(Color.textOnBrand).accessibilityAddTraits(.isHeader)
                    Text("\(s.totalUnits) units • \(s.rented) rented • \(s.available) available").font(.footnote).foregroundStyle(Color.textHeaderSecondary)
                }
                Spacer()
                Button { Task { await sync.refresh(context: context, business: business) } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Color.textOnBrand).frame(width: 44, height: 44)
                }
                .disabled(sync.state == .syncing).accessibilityLabel("Refresh locations").accessibilityIdentifier("rentro.map.refresh")
            }
            RentroSearchField(text: $query, prompt: "Search a unit", id: "rentro.map.search")
            Picker("View", selection: $showList) {
                Text("Map").tag(false); Text("List").tag(true)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("rentro.map.mode")
        }
        .padding(Space.s16)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)                 // map overlay is chrome: capped, but it wraps rather than truncates
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.brandSolid, in: RoundedRectangle(cornerRadius: Radius.r16))
        .padding(.horizontal, Space.s16)
    }

    private func map(_ shown: [RentalDevice], _ latest: [UUID: LocationPoint], _ now: Date) -> some View {
        Map(position: $position, selection: $selected) {
            ForEach(shown.compactMap { d in latest[d.id].map { (d, $0) } }, id: \.0.id) { d, p in
                Annotation(d.unitCode, coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)) {
                    let f = Locations.freshness(p, now: now), stale = f == .stale
                    HStack(spacing: Space.s4) {
                        Image(systemName: "iphone").font(.caption2)
                        Text(Locations.pinLabel(d.unitCode)).font(.subheadline.weight(.bold))
                    }
                    // Stale = hollow with a dashed edge: dimmed (PRD 4.6) yet legible, and not told apart by colour alone.
                    .foregroundStyle(stale ? Color.brandSolid : Color.textOnBrand).padding(.horizontal, Space.s12).frame(minHeight: 36)
                    .background(stale ? Color.bgSurface : Color.brandSolid, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.brandSolid, style: StrokeStyle(lineWidth: 2, dash: stale ? [4, 3] : [])))
                    .opacity(f == .aging ? 0.85 : 1)
                    .overlay(Capsule().stroke(selected == d.id ? Color.textPrimary : .clear, lineWidth: 3).padding(-3))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(d.model), \(d.unitCode), last reported \(Age.text(from: p.measuredAt, now: now))")
                }
                .tag(d.id)
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
    }

    private func list(_ shown: [RentalDevice], _ latest: [UUID: LocationPoint], _ now: Date) -> some View {
        ScrollView {
            LazyVStack(spacing: Space.s12) {
                ForEach(shown) { d in
                    let p = latest[d.id], f = Locations.freshness(p, now: now)
                    NavigationLink(value: d) {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text(d.model).font(.headline).foregroundStyle(Color.textPrimary)
                            Text(d.unitCode).font(.footnote).foregroundStyle(Color.textSecondary)
                            FreshnessBadge(freshness: f)
                            Text(freshnessLine(p, f, now)).font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain).accessibilityElement(children: .combine)
                }
                if shown.isEmpty { EmptyState(title: "No matches", message: "Try another search.", symbol: "magnifyingglass") }
            }
            .padding(Space.s16)
        }
        .accessibilityIdentifier("rentro.map.list")
    }

    @ViewBuilder private func bottomCard(_ latest: [UUID: LocationPoint], _ now: Date) -> some View {
        if let d = devices.first(where: { $0.id == selected }), let p = latest[d.id] {
            let f = Locations.freshness(p, now: now)
            VStack(alignment: .leading, spacing: Space.s8) {
                Text(d.model).font(.headline).foregroundStyle(Color.textPrimary)
                Text("\(d.unitCode) · \(statusText(d))").font(.footnote).foregroundStyle(Color.textSecondary)
                FreshnessBadge(freshness: f)
                Text(freshnessLine(p, f, now)).font(.footnote).foregroundStyle(Color.textPrimary)
                HStack(spacing: Space.s12) {
                    NavigationLink(value: d) { Text("Device Details").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).tint(.brandSolid).accessibilityIdentifier("rentro.map.details")
                    Button { openURL(URL(string: "https://www.icloud.com/find")!) } label: {
                        Label("Open Find My", systemImage: "arrow.up.forward.app").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(.brandSolid)
                }
            }
            .card().dynamicTypeSize(...DynamicTypeSize.accessibility1).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s16).padding(.bottom, Space.s8).accessibilityIdentifier("rentro.map.sheet")
        } else {
            summaryCard(latest, now)
        }
    }

    private func summaryCard(_ latest: [UUID: LocationPoint], _ now: Date) -> some View {
        let fs = devices.map { Locations.freshness(latest[$0.id], now: now) }
        func n(_ f: LocationFreshness) -> Int { fs.filter { $0 == f }.count }
        return VStack(alignment: .leading, spacing: Space.s4) {
            if latest.isEmpty {
                Text("No locations received yet").font(.headline).foregroundStyle(Color.textPrimary)
                Text("Pair a device and enable location sharing to show a last-known location.").font(.footnote).foregroundStyle(Color.textSecondary)
            } else {
                Text("Last-known locations").font(.headline).foregroundStyle(Color.textPrimary)
                Text("\(n(.recent)) recent · \(n(.aging)) aging · \(n(.stale)) stale · \(n(.neverReported)) not reported")
                    .font(.footnote).foregroundStyle(Color.textSecondary).accessibilityIdentifier("rentro.map.summary")
            }
            syncNote
        }
        .card().dynamicTypeSize(...DynamicTypeSize.accessibility1).fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.s16).padding(.bottom, Space.s8)
    }

    @ViewBuilder private var syncNote: some View {
        switch sync.state {
        case .notConfigured: Text("Location sync isn't set up on this build yet.").font(.caption).foregroundStyle(Color.textSecondary).accessibilityIdentifier("rentro.map.syncnote")
        case .failed(let m): Text("Couldn't refresh: \(m)").font(.caption).foregroundStyle(Color.textDanger)
        default: EmptyView()
        }
    }

    // MARK: helpers

    private func statusText(_ d: RentalDevice) -> String {
        switch Derive.status(of: d, rentals: rentals) { case .rented: String(localized: "Currently rented"); case .available: String(localized: "Available"); case .maintenance: String(localized: "In maintenance") }
    }
    private func freshnessLine(_ p: LocationPoint?, _ f: LocationFreshness, _ now: Date) -> String {
        guard let p else { return String(localized: "Pair a tracker to see where this iPhone last reported from.") }
        let base = String(localized: "Last reported \(Age.text(from: p.measuredAt, now: now)) · ±\(Int(p.accuracyM)) m")
        return f == .stale ? base + String(localized: " — may no longer be current.") : base
    }
    private func focusRequested() {
        guard let id = store.mapFocus else { return }
        showList = false
        selected = id
        if let p = Locations.latest(points)[id] {
            position = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                                  span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
        store.mapFocus = nil
    }
}
