import SwiftData
import SwiftUI

/// Pushed from Home shortcuts (PRD 3: Customers, Payments and Alerts are routes, never extra tabs).
struct ShortcutRow: View {
    let symbol: String
    let title: LocalizedStringKey
    var detail: String?
    var body: some View {
        HStack(spacing: Space.s16) {
            IconTile(symbol: symbol)
            Text(title).font(.headline).foregroundStyle(Color.textPrimary)
            Spacer()
            if let detail { Text(detail).font(.footnote).foregroundStyle(Color.textSecondary) }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.textSecondary).accessibilityHidden(true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: S27 Alerts. Figma 44:1163 / 44:1874

struct AlertsView: View {
    @Environment(\.modelContext) private var context
    let business: Business
    @Query private var rentals: [Rental]
    @Query private var records: [AlertRecord]
    @State private var filter: AlertKind?

    init(business: Business) {
        self.business = business
        let id = business.id
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
        _records = Query(filter: #Predicate<AlertRecord> { $0.businessID == id })
    }

    var body: some View {
        let now = Date.now
        let all = Alerts.derive(rentals: rentals, now: now, calendar: business.calendar)
        let read = Set(records.map(\.key))
        let rows = all.filter { filter == nil || $0.kind == filter }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                FilterPills(options: [nil] + AlertKind.allCases.map(Optional.some), selection: $filter,
                            title: { $0?.shortTitle ?? "All" }, id: "rentro.alerts.filter")
                if rows.isEmpty {
                    EmptyState(title: all.isEmpty ? "You're all caught up" : "No matches",
                               message: all.isEmpty ? "Due, overdue and payment alerts appear here, even if push is off." : "Try another filter.",
                               symbol: "bell", action: all.isEmpty ? nil : ("Clear Filters", { filter = nil }))
                }
                ForEach(rows) { a in
                    let unread = !read.contains(a.key)
                    NavigationLink(value: a.rental) {
                        HStack(spacing: Space.s12) {
                            Circle().fill(a.kind == .overdue ? Color.textDanger : Color.brandSelected).frame(width: 8, height: 8)
                                .opacity(unread ? 1 : 0.25).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Space.s4) {
                                Text(a.kind.title).font(unread ? .headline : .body).foregroundStyle(Color.textPrimary)
                                Text(Alerts.detail(a, now: now, timeZone: business.timeZone)).font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                        .card()
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(unread ? String(localized: "Unread") : String(localized: "Read"))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { try? context.markRead([a.key], businessID: business.id) })
                }
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Mark All Read") { try? context.markRead(all.map(\.key), businessID: business.id) }
                    .disabled(all.allSatisfy { read.contains($0.key) })
            }
        }
    }
}

// MARK: S21 Customers. Figma 44:931 / 44:1642

struct CustomersView: View {
    let business: Business
    @Query private var customers: [Customer]
    @State private var query = ""
    @State private var adding = false

    init(business: Business) {
        self.business = business
        let id = business.id
        _customers = Query(filter: #Predicate<Customer> { $0.businessID == id }, sort: \.fullName)
    }

    private var rows: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits = q.filter(\.isNumber)
        return q.isEmpty ? customers : customers.filter { $0.fullName.localizedCaseInsensitiveContains(q) || (!digits.isEmpty && $0.phone.contains(digits)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                RentroSearchField(text: $query, prompt: "Search customers", id: "rentro.customers.search")
                if customers.isEmpty {
                    EmptyState(title: "No customers yet", message: "Customers you add appear here.", symbol: "person.2", action: ("Add Customer", { adding = true }))
                } else if rows.isEmpty {
                    EmptyState(title: "No matches", message: "Try another search or filter.", symbol: "magnifyingglass", action: ("Clear Filters", { query = "" }))
                }
                ForEach(rows) { c in
                    NavigationLink(value: c) {
                        let n = (c.rentals ?? []).count
                        let who = VStack(alignment: .leading, spacing: Space.s4) {
                            Text(c.fullName).font(.headline).foregroundStyle(Color.textPrimary)
                            Text(c.phone.isEmpty ? String(localized: "No phone") : Phone.display(c.phone)).font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        let count = Text(n == 1 ? "1 rental" : "\(n) rentals").font(.footnote).foregroundStyle(Color.textSecondary)
                        ViewThatFits(in: .horizontal) {                       // count beside the name while it fits, below it otherwise
                            HStack { who; Spacer(); count }
                            VStack(alignment: .leading, spacing: Space.s4) { who; count }
                        }
                        .card()
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Customers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add Customer", systemImage: "plus") }.accessibilityIdentifier("rentro.customers.add")
            }
        }
        .sheet(isPresented: $adding) { CustomerFormView(business: business) }
    }
}

/// S22 Customer Detail. Figma 44:969 / 44:1680
struct CustomerDetailView: View {
    @Environment(AppStore.self) private var store
    let customer: Customer
    let business: Business
    @State private var editing = false

    var body: some View {
        let rentals = (customer.rentals ?? []).sorted { $0.pickupAt > $1.pickupAt }
        let outstanding = rentals.filter { $0.status != .cancelled }.reduce(0) { $0 + max($1.balanceDueIDR, 0) }
        let now = Date.now
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                SummaryCard(title: "Contact") {
                    AlignedLabelValueRow(label: "Name", value: customer.fullName)
                    Divider()
                    AlignedLabelValueRow(label: "Phone", value: customer.phone.isEmpty ? "-" : Phone.display(customer.phone))
                    Divider()
                    AlignedLabelValueRow(label: "Outstanding", value: outstanding.rupiah)
                }
                Button("New Rental") { store.preselectedCustomer = customer; store.newRentalPresented = true }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rentro.customer.newrental")
                SectionHeading(title: "Rentals") { EmptyView() }
                if rentals.isEmpty { Text("No rentals yet").foregroundStyle(Color.textSecondary).card() }
                ForEach(rentals) { r in
                    NavigationLink(value: r) { RentalCard(rental: r, badge: r.badge(now: now, calendar: business.calendar)) }.buttonStyle(.plain)
                }
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle(customer.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) { CustomerFormView(business: business, customer: customer) }
    }
}

// MARK: S24 Payments & Deposits. Figma 44:1048 / 44:1759

private enum LedgerFilter: CaseIterable {
    case all, payments, deposits, refunds
    var title: String { switch self { case .all: String(localized: "All"); case .payments: String(localized: "Payments"); case .deposits: String(localized: "Deposits"); case .refunds: String(localized: "Refunds") } }
    func includes(_ c: PaymentCategory) -> Bool {
        switch self {
        case .all: true
        case .payments: c == .rentalPayment || c == .adjustment
        case .deposits: c == .depositReceived
        case .refunds: c == .depositRefunded || c == .depositDeduction
        }
    }
}

struct PaymentsView: View {
    let business: Business
    @Query private var entries: [PaymentEntry]
    @Query private var rentals: [Rental]
    @State private var filter = LedgerFilter.all

    init(business: Business) {
        self.business = business
        let id = business.id
        _entries = Query(filter: #Predicate<PaymentEntry> { $0.businessID == id }, sort: \.createdAt, order: .reverse)
        _rentals = Query(filter: #Predicate<Rental> { $0.businessID == id })
    }

    var body: some View {
        // Deposits are a liability and are excluded from revenue (PRD S24).
        let revenue = rentals.reduce(0) { $0 + $1.amountPaidIDR }
        let outstanding = rentals.filter { $0.status != .cancelled }.reduce(0) { $0 + max($1.balanceDueIDR, 0) }
        let held = rentals.reduce(0) { $0 + $1.depositHeldIDR }
        let rows = entries.filter { filter.includes($0.category) }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                SummaryCard(title: "Summary") {
                    AlignedLabelValueRow(label: "Rental revenue", value: revenue.rupiah)
                    Divider()
                    AlignedLabelValueRow(label: "Outstanding", value: outstanding.rupiah)
                    Divider()
                    AlignedLabelValueRow(label: "Held deposits", value: held.rupiah)
                }
                FilterPills(options: LedgerFilter.allCases, selection: $filter, title: \.title, id: "rentro.payments.filter")
                if rows.isEmpty {
                    EmptyState(title: entries.isEmpty ? "No payments recorded yet" : "No matches",
                               message: entries.isEmpty ? "Payments and deposits you record appear here." : "Try another search or filter.",
                               symbol: "banknote", action: entries.isEmpty ? nil : ("Clear Filters", { filter = .all }))
                }
                ForEach(rows) { e in
                    if let r = e.rental {
                        NavigationLink(value: r) { entryRow(e, r) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle("Payments & Deposits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func entryRow(_ e: PaymentEntry, _ r: Rental) -> some View {
        let out = e.category == .depositRefunded
        let sign = out ? "− " : (e.category == .depositDeduction ? "" : "+ ")
        return HStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("\(e.category.shortTitle) · \(r.code)").foregroundStyle(Color.textPrimary)
                Text(e.paidAt.stamp(business.timeZone) + " · " + e.method.title).font(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text(sign + e.amountIDR.rupiah).font(.subheadline.weight(.semibold))
                .foregroundStyle(out ? Color.textDanger : e.category == .depositDeduction ? Color.textSecondary : Color.textSuccess)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

extension PaymentCategory {
    var shortTitle: String {
        switch self {
        case .rentalPayment: "Payment"
        case .depositReceived: "Deposit"
        case .depositRefunded: String(localized: "Refund")
        case .depositDeduction: "Deduction"
        case .adjustment: "Adjustment"
        }
    }
}
