import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var size
    let business: Business
    @Query private var rentals: [Rental]
    @Query private var devices: [RentalDevice]
    @Query private var alertRecords: [AlertRecord]

    init(business: Business) {
        self.business = business
        let id = business.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id }, sort: \.pickupAt)
        _devices = Query(filter: #Predicate<RentalDevice> { $0.businessID == id }, sort: \.unitCode)
        _alertRecords = Query(filter: #Predicate<AlertRecord> { $0.businessID == id })
    }

    var body: some View {
        @Bindable var store = store
        let now = Date.now
        let s = Derive.summary(devices: devices, rentals: rentals, now: now, calendar: business.calendar)
        let activity = Derive.activity(rentals: rentals, now: now, calendar: business.calendar)
        NavigationStack {
            TabPage(hero: Hero(title: greeting(now), subtitle: "Your rental business at a glance",
                               query: $store.rentalQuery, searchID: "rentro.home.search",
                               onSubmit: { store.show(rentals: .all) })) {
                SectionHeading(title: "Fleet overview") {
                    Text("Today · \(now.formatted(Date.FormatStyle(timeZone: business.timeZone).day().month(.abbreviated)))")
                        .font(.footnote).foregroundStyle(Color.textAccent)
                }
                if s.totalUnits == 0 {
                    EmptyState(title: "No devices yet", message: "Add your first rental iPhone to get started.",
                               symbol: "iphone", action: ("Add Device", { store.show(devices: .all); store.addingDevice = true }))
                } else {
                    LazyVGrid(columns: size.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: Space.s12), GridItem(.flexible())], spacing: Space.s12) {
                        FleetKpiCard(symbol: "iphone", value: s.totalUnits, label: "Total units") { store.show(devices: .all) }
                        FleetKpiCard(symbol: "arrow.up.right.circle", value: s.rented, label: "Currently rented") { store.show(rentals: .active) }
                        FleetKpiCard(symbol: "checkmark.circle", value: s.available, label: "Available") { store.show(devices: .available) }
                        FleetKpiCard(symbol: "exclamationmark.triangle", value: s.overdue, label: "Overdue", warning: true) { store.show(rentals: .overdue) }
                    }
                }
                Button("New Rental") { store.newRentalPresented = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("rentro.home.newrental")
                let unread = Alerts.derive(rentals: rentals, now: now, calendar: business.calendar).filter { a in !alertRecords.contains { $0.key == a.key } }.count
                NavigationLink { AlertsView(business: business) } label: {
                    ShortcutRow(symbol: "bell", title: "Alerts", detail: unread > 0 ? String(localized: "\(unread) unread") : nil)
                }.buttonStyle(.plain).accessibilityIdentifier("rentro.home.alerts")
                NavigationLink { CustomersView(business: business) } label: { ShortcutRow(symbol: "person.2", title: "Customers") }
                    .buttonStyle(.plain).accessibilityIdentifier("rentro.home.customers")
                NavigationLink { PaymentsView(business: business) } label: { ShortcutRow(symbol: "banknote", title: "Payments & Deposits") }
                    .buttonStyle(.plain).accessibilityIdentifier("rentro.home.payments")
                SectionHeading(title: "Today's activity") {
                    Button { store.show(rentals: .all) } label: {
                        Label("View all", systemImage: "chevron.right").labelStyle(.titleAndIcon).font(.footnote.weight(.semibold))
                    }.foregroundStyle(Color.textAccent).frame(minHeight: 44)
                }
                .padding(.top, Space.s8)
                if activity.isEmpty {
                    Text("No activity scheduled today").foregroundStyle(Color.textSecondary).card()
                }
                ForEach(Array(activity.enumerated()), id: \.offset) { _, a in
                    ActivityRow(activity: a, timeZone: business.timeZone)
                }
            }
            .navigationDestination(for: Rental.self) { RentalDetailView(rental: $0, business: business) }
            .navigationDestination(for: Customer.self) { CustomerDetailView(customer: $0, business: business) }
        }
    }

    private func greeting(_ now: Date) -> LocalizedStringKey {
        let h = business.calendar.component(.hour, from: now)
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
}

private struct ActivityRow: View {
    let activity: Activity
    let timeZone: TimeZone

    var body: some View {
        let (symbol, title, rental, warn) = parts
        NavigationLink(value: rental) {
            HStack(spacing: Space.s16) {
                IconTile(symbol: symbol, warning: warn)
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(title).font(.headline).foregroundStyle(Color.textPrimary)
                    Text("\(rental.deviceModel) · \(rental.customerName)").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var parts: (String, String, Rental, Bool) {
        func time(_ d: Date) -> String { d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)) }
        switch activity {
        case .pickup(let r): return ("arrow.up.right.circle", String(localized: "Pickup • \(time(r.pickupAt))"), r, false)
        case .return(let r): return ("arrow.down.left.circle", String(localized: "Return • \(time(r.expectedReturnAt))"), r, false)
        case .overdue(let r): return ("exclamationmark.triangle", String(localized: "Overdue rental"), r, true)
        }
    }
}
