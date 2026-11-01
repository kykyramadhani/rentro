import SwiftData
import SwiftUI

struct RentalsView: View {
    @Environment(AppStore.self) private var store
    let business: Business
    @Query private var rentals: [Rental]
    @State private var path: [Rental] = []

    init(business: Business) {
        self.business = business
        let id = business.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id }, sort: \.pickupAt, order: .reverse)
    }

    var body: some View {
        @Bindable var store = store
        let now = Date.now
        let rows = Derive.rentals(rentals, filter: store.rentalFilter, query: store.rentalQuery, now: now, calendar: business.calendar)
        NavigationStack(path: $path) {
            TabPage(hero: Hero(title: "Rentals", subtitle: "Manage every booking in one place",
                               query: $store.rentalQuery, searchID: "rentro.rentals.search")) {
                SectionHeading(title: "Bookings") {
                    Button { store.newRentalPresented = true } label: {
                        Label("New", systemImage: "plus").font(.footnote.weight(.semibold)).frame(minHeight: 44)
                    }
                    .foregroundStyle(Color.textAccent)
                    .accessibilityIdentifier("rentro.rentals.new")
                }
                FilterPills(options: RentalFilter.allCases, selection: $store.rentalFilter, title: \.title, id: "rentro.rentals.filter")
                if rows.isEmpty {
                    if rentals.isEmpty {
                        EmptyState(title: "No rentals yet", message: "Bookings you create will appear here.", symbol: "list.clipboard",
                                   action: ("New Rental", { store.newRentalPresented = true }))
                    } else {
                        EmptyState(title: "No matches", message: "Try another search or filter.", symbol: "magnifyingglass",
                                   action: ("Clear Filters", { store.rentalFilter = .all; store.rentalQuery = "" }))
                    }
                }
                ForEach(rows) { r in
                    NavigationLink(value: r) { RentalCard(rental: r, badge: r.badge(now: now, calendar: business.calendar)) }
                        .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: Rental.self) { RentalDetailView(rental: $0, business: business) }
        }
        .onChange(of: store.selectedRental) { _, r in
            if let r { path = [r] }     // opened from the New Rental success screen
        }
        .onAppear { if let r = store.selectedRental { path = [r] } }
    }
}

extension RentalFilter {
    var title: String { switch self { case .all: String(localized: "All"); case .active: String(localized: "Active"); case .upcoming: String(localized: "Upcoming"); case .overdue: String(localized: "Overdue") } }
}

struct RentalCard: View {
    let rental: Rental
    let badge: RentalBadge
    var body: some View {
        let texts = VStack(alignment: .leading, spacing: Space.s4) {
            Text(rental.code).font(.caption).foregroundStyle(Color.textSecondary)
            Text(rental.customerName).font(.headline).foregroundStyle(Color.textPrimary)
            Text("\(rental.deviceModel) · \(rental.unitCode)").font(.footnote).foregroundStyle(Color.textSecondary)
        }
        // Status pill beside the text while it fits, above it at large sizes.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Space.s12) { texts; Spacer(minLength: Space.s8); StatusPill(text: badge.title, tone: badge.tone) }
            VStack(alignment: .leading, spacing: Space.s8) { StatusPill(text: badge.title, tone: badge.tone); texts }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
