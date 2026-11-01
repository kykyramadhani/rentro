import SwiftData
import SwiftUI

extension DeviceFilter {
    var title: String { switch self { case .all: String(localized: "All"); case .available: String(localized: "Available"); case .rented: String(localized: "Rented") } }
}

struct DevicesView: View {
    @Environment(AppStore.self) private var store
    let business: Business
    @Query private var devices: [RentalDevice]
    @Query private var rentals: [Rental]

    init(business: Business) {
        self.business = business
        let id = business.id
        _devices = Query(filter: #Predicate<RentalDevice> { $0.businessID == id }, sort: \.unitCode)
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
    }

    var body: some View {
        @Bindable var store = store
        let rows = Derive.devices(devices, rentals: rentals, filter: store.deviceFilter, query: store.deviceQuery)
        NavigationStack {
            TabPage(hero: Hero(title: "Devices", subtitle: "All rental units, neatly organized",
                               query: $store.deviceQuery, searchID: "rentro.devices.search")) {
                SectionHeading(title: "Inventory") {
                    Button { store.addingDevice = true } label: {
                        Label("Add unit", systemImage: "plus").font(.footnote.weight(.semibold)).frame(minHeight: 44)
                    }
                    .foregroundStyle(Color.textAccent)
                    .accessibilityIdentifier("rentro.devices.add")
                }
                FilterPills(options: DeviceFilter.allCases, selection: $store.deviceFilter, title: \.title, id: "rentro.devices.filter")
                if rows.isEmpty {
                    if devices.isEmpty {
                        EmptyState(title: "No devices yet", message: "Add your first rental iPhone to get started.", symbol: "iphone",
                                   action: ("Add Device", { store.addingDevice = true }))
                    } else {
                        EmptyState(title: "No matches", message: "Try another search or filter.", symbol: "magnifyingglass",
                                   action: ("Clear Filters", { store.deviceFilter = .all; store.deviceQuery = "" }))
                    }
                }
                ForEach(rows) { d in
                    NavigationLink(value: d) { DeviceCard(device: d, status: Derive.status(of: d, rentals: rentals)) }
                        .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: RentalDevice.self) { DeviceDetailView(device: $0, business: business) }
            .sheet(isPresented: $store.addingDevice) { DeviceFormView(business: business) }
        }
    }
}

struct DeviceCard: View {
    let device: RentalDevice
    let status: DeviceStatus
    @Environment(\.dynamicTypeSize) private var size
    @ScaledMetric(relativeTo: .title) private var tile: CGFloat = 64
    var body: some View {
        HStack(spacing: Space.s16) {
            if !size.isAccessibilitySize {          // decoration gives way to text at large sizes
                Image(systemName: "iphone").font(.title).foregroundStyle(Color.iconDefault)
                    .frame(width: tile, height: tile)
                    .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.r12))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(device.model).font(.headline).foregroundStyle(Color.textPrimary)
                Text("\(device.unitCode) · \(device.capacityGB)GB").font(.footnote).foregroundStyle(Color.textSecondary)
                StatusPill(text: status.title, tone: status.tone).padding(.top, Space.s4)
            }
            Spacer()
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct DeviceDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(LocationSync.self) private var sync
    @Query private var rentals: [Rental]
    @Query private var points: [LocationPoint]
    @State private var editing = false
    @State private var maintaining = false
    @State private var pairing = false
    @State private var confirmRevoke = false
    @State private var trackerError: String?
    let device: RentalDevice
    let business: Business

    init(device: RentalDevice, business: Business) {
        self.device = device
        self.business = business
        let id = business.id, did = device.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
        _points = Query(filter: #Predicate<LocationPoint> { $0.deviceID == did }, sort: \.measuredAt, order: .reverse)
    }

    private var activeRental: Rental? { rentals.first(where: { $0.device?.id == device.id && $0.status == .active }) }

    var body: some View {
        let status = Derive.status(of: device, rentals: rentals)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(status)
                VStack(alignment: .leading, spacing: Space.s16) {
                    currentRental(status)
                    trackingSection
                    actions
                    manage
                    if let trackerError { Text(trackerError).font(.footnote).foregroundStyle(Color.textDanger) }
                }
                .padding(Space.s20)
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        // Figma S15 puts the title on the teal; forcing the system bar teal clashed with its glass buttons (illegible Back/Edit),
        // so the bar stays native and the teal hero starts directly beneath it.
        .navigationTitle(device.model)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.accessibilityIdentifier("rentro.device.edit") } }
        .sheet(isPresented: $editing) { DeviceFormView(business: business, device: device) }
        .sheet(isPresented: $maintaining) { MaintenanceSheet(device: device) }
        .sheet(isPresented: $pairing) { PairTrackerSheet(device: device, business: business) }
        .confirmationDialog("Revoke the tracker on \(device.unitCode)?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Revoke Tracker", role: .destructive) { Task { await revoke() } }
        } message: { Text("Locations it sends afterwards are ignored. Existing history stays until you delete it.") }
    }

    // MARK: Figma S15 pieces

    private func hero(_ status: DeviceStatus) -> some View {
        let details = [device.unitCode, "\(device.capacityGB)GB", device.color].filter { !$0.isEmpty }.joined(separator: " · ")
        let pill = Text(status.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Color.textOnSoft).fixedSize()
            .padding(.horizontal, Space.s12).padding(.vertical, Space.s4).background(Color.bgSubtle, in: Capsule())
        let tile = Image(systemName: "iphone").font(.system(size: 44)).foregroundStyle(Color.textOnBrand.opacity(0.9))
            .frame(width: 104, height: 84).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.r16)).accessibilityHidden(true)
        return VStack(alignment: .leading, spacing: Space.s16) {
            Text(details).font(.subheadline).foregroundStyle(Color.textHeaderSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom) { pill; Spacer(); tile }
                VStack(alignment: .leading, spacing: Space.s12) { pill }      // the decorative tile gives way to text at large sizes
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s20).padding(.top, Space.s16).padding(.bottom, Space.s24)
        .background(Color.brandSolid)
        .accessibilityElement(children: .combine).accessibilityLabel("\(device.model), \(details), \(status.title)")
    }

    private func currentRental(_ status: DeviceStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Current rental").font(.headline).foregroundStyle(Color.textPrimary); Spacer(); detailsLink }
                VStack(alignment: .leading, spacing: Space.s4) { Text("Current rental").font(.headline).foregroundStyle(Color.textPrimary); detailsLink }
            }
            .accessibilityElement(children: .contain)
            VStack(alignment: .leading, spacing: Space.s8) {
                if let r = activeRental {
                    Text(r.customerName).font(.headline).foregroundStyle(Color.textPrimary)
                    AlignedLabelValueRow(label: "Pickup", value: (r.actualPickupAt ?? r.pickupAt).stamp(business.timeZone))
                    AlignedLabelValueRow(label: "Return", value: r.expectedReturnAt.stamp(business.timeZone))
                } else {
                    Text(status == .maintenance ? "In maintenance" : "Not rented right now").font(.headline).foregroundStyle(Color.textPrimary)
                    if device.lifecycle == .maintenance, !device.maintenanceNote.isEmpty {
                        Text(device.maintenanceNote).font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder private var detailsLink: some View {
        if let r = activeRental {
            NavigationLink { RentalDetailView(rental: r, business: business) } label: {
                Label("Details", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.footnote.weight(.semibold)).frame(minHeight: 44)
            }
            .foregroundStyle(Color.textAccent).accessibilityIdentifier("rentro.device.rentaldetails")
        }
    }

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Location tracking").font(.headline).foregroundStyle(Color.textPrimary); Spacer(); historyLink }
                VStack(alignment: .leading, spacing: Space.s4) { Text("Location tracking").font(.headline).foregroundStyle(Color.textPrimary); historyLink }
            }
            if let p = points.first {
                LocationCard(point: p, now: .now).card()
            } else {
                // Truthful until a consented tracker reports (PRD 4.6).
                Label("No location received", systemImage: "location.slash").foregroundStyle(Color.textSecondary).card()
                    .accessibilityIdentifier("rentro.device.nolocation")
            }
        }
    }

    private var historyLink: some View {
        NavigationLink { LocationHistoryView(device: device, business: business) } label: {
            Label("History", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.footnote.weight(.semibold)).frame(minHeight: 44)
        }
        .foregroundStyle(Color.textAccent).accessibilityIdentifier("rentro.device.history")
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s12) { viewLocation; findMy }
            VStack(spacing: Space.s12) { viewLocation; findMy }
        }
    }
    private var viewLocation: some View {
        Button { store.mapFocus = device.id; store.tab = .map } label: { Label("View location", systemImage: "scope") }
            .buttonStyle(PrimaryButtonStyle()).disabled(points.isEmpty).accessibilityIdentifier("rentro.device.viewlocation")
    }
    private var findMy: some View {
        Button { openURL(URL(string: "https://www.icloud.com/find")!) } label: {
            Label("Open Find My", systemImage: "arrow.up.forward.app").font(.headline).foregroundStyle(Color.textOnSoft)
                .frame(maxWidth: .infinity, minHeight: 48).background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.r16))
        }
        .buttonStyle(.plain).accessibilityIdentifier("rentro.device.findmy")
    }

    private var manage: some View {
        VStack(alignment: .leading, spacing: 0) {
            manageRow("Maintenance", "wrench.and.screwdriver", id: "rentro.device.maintenance") { maintaining = true }
            Divider()
            manageRow("Pair Tracker", "qrcode", id: "rentro.device.pair") { pairing = true }
            if !points.isEmpty {
                Divider()
                manageRow("Revoke Tracker", "xmark.circle", id: "rentro.device.revoke", destructive: true) { confirmRevoke = true }
            }
        }
        .card()
    }
    private func manageRow(_ title: LocalizedStringKey, _ symbol: String, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).foregroundStyle(destructive ? Color.textDanger : Color.textAccent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func revoke() async {
        do { try await sync.gateway.revoke(deviceID: device.id); trackerError = nil }
        catch let e as TransportError { trackerError = e == .notConfigured ? String(localized: "Tracker revocation needs iCloud setup.") : e.userMessage }
        catch { trackerError = error.localizedDescription }
    }
}

/// S17 Device Maintenance. Figma 44:887 / 44:1598.
struct MaintenanceSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let device: RentalDevice
    @State private var status: DeviceLifecycle
    @State private var note: String
    @State private var error: String?

    init(device: RentalDevice) {
        self.device = device
        _status = State(initialValue: device.lifecycle)
        _note = State(initialValue: device.maintenanceNote)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    RentroFormField(label: "Status") {
                        Picker("Status", selection: $status) {
                            Text("Available").tag(DeviceLifecycle.enabled)
                            Text("Maintenance").tag(DeviceLifecycle.maintenance)
                            Text("Retired").tag(DeviceLifecycle.retired)
                        }
                        .labelsHidden().tint(.textPrimary).accessibilityIdentifier("rentro.maintenance.status")
                    }
                    if status == .maintenance {
                        RentroFormField(label: "Issue") { TextField("Cracked screen, battery swelling…", text: $note).accessibilityIdentifier("rentro.maintenance.note") }
                    }
                    Text("A device in maintenance or retired cannot be booked. History is kept.").font(.footnote).foregroundStyle(Color.textSecondary)
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                    Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rentro.maintenance.save")
                }
                .padding(Space.s20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        do { try context.setDeviceStatus(device, status, note: note); dismiss() } catch { self.error = error.localizedDescription }
    }
}
