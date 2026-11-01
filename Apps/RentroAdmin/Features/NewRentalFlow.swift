import SwiftData
import SwiftUI

@Observable
final class RentalDraft {
    var customer: Customer?
    var device: RentalDevice?
    var pickupAt: Date
    var returnAt: Date
    var discount = 0
    var paidNow = 0
    var depositNow = false
    var method = PaymentMethod.cash
    let key = UUID().uuidString       // one key per wizard run: a double tap on Confirm creates one rental

    init(now: Date = .now) {
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
        pickupAt = hour
        returnAt = hour.addingTimeInterval(86400)
    }

    var started: Bool { customer != nil }
    var quote: Quote? { device.map { Billing.quote(dailyRateIDR: $0.dailyRateIDR, from: pickupAt, to: returnAt) } }
}

private enum Step: Hashable { case device, price, review, done }

/// S05–S08 New Rental. Figma 45:578/45:919, 45:670/45:1011, 44:1202/44:1913, 44:1243/44:1954 (not the legacy single-screen frame).
/// "1 billable day" / "3 billable days": explicit one/other keys so each language words them itself.
private func billableDays(_ n: Int) -> String { n == 1 ? String(localized: "1 billable day") : String(localized: "\(n) billable days") }

struct NewRentalFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    let business: Business

    @State private var draft = RentalDraft()
    @State private var path: [Step] = []
    @State private var created: Rental?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack(path: $path) {
            CustomerStep(business: business, draft: draft) { path.append(.device) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .device: DeviceStep(business: business, draft: draft) { path.append(.price) }
                    case .price: PriceStep(business: business, draft: draft) { path.append(.review) }
                    case .review:
                        ReviewStep(business: business, draft: draft, changeSchedule: { path = [.device] }) { created = $0; path.append(.done) }
                    case .done: DoneStep(rental: created, done: { dismiss() }, view: open)
                    }
                }
        }
        .onAppear {
            if let c = store.preselectedCustomer { draft.customer = c; store.preselectedCustomer = nil }   // from Customer Detail (S22)
        }
        .interactiveDismissDisabled(draft.started && created == nil)
        .confirmationDialog("Discard this rental?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private func cancel() { if draft.started { confirmDiscard = true } else { dismiss() } }

    private func open(startPickup: Bool) {
        store.selectedRental = created
        store.startPickupOnOpen = startPickup
        store.tab = .rentals
        dismiss()
    }
}

/// Header + scroll content + pinned primary action shared by all four steps.
private struct StepPage<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var primary: LocalizedStringKey
    var enabled = true
    var id: String
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                Text(subtitle).font(.subheadline).foregroundStyle(Color.textSecondary)
                content
            }
            .padding(Space.s20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgCanvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(primary, action: action).buttonStyle(PrimaryButtonStyle()).disabled(!enabled)
                .accessibilityIdentifier(id)
                .padding(.horizontal, Space.s20).padding(.vertical, Space.s12)
                .background(Color.bgCanvas)
        }
        .navigationTitle(title)
    }
}

// MARK: Step 1 · Customer (S05)

private struct CustomerStep: View {
    let business: Business
    @Bindable var draft: RentalDraft
    let next: () -> Void
    @Query private var customers: [Customer]
    @State private var query = ""
    @State private var adding = false
    private var selectCustomerLabel: some View { Text("SELECT CUSTOMER").font(.caption).foregroundStyle(Color.textSecondary) }
    private var addCustomerButton: some View {
        Button { adding = true } label: { Label("Add Customer", systemImage: "plus").font(.footnote.weight(.semibold)).frame(minHeight: 44) }
            .foregroundStyle(Color.textAccent).accessibilityIdentifier("rentro.new.addcustomer")
    }

    init(business: Business, draft: RentalDraft, next: @escaping () -> Void) {
        self.business = business
        self.draft = draft
        self.next = next
        let id = business.id
        _customers = Query(filter: #Predicate<Customer> { $0.businessID == id }, sort: \.fullName)
    }

    private var rows: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? customers : customers.filter { $0.fullName.localizedCaseInsensitiveContains(q) || $0.phone.contains(q.filter(\.isNumber)) && !q.filter(\.isNumber).isEmpty }
    }

    var body: some View {
        StepPage(title: "New Rental", subtitle: "Step 1 of 4 · Customer", primary: "Continue",
                 enabled: draft.customer != nil, id: "rentro.new.continue1", action: next) {
            RentroSearchField(text: $query, prompt: "Search customers", id: "rentro.new.customersearch")
            if customers.isEmpty {
                EmptyState(title: "No customers yet", message: "Add the person renting this iPhone.", symbol: "person.crop.circle.badge.plus",
                           action: ("Add Customer", { adding = true }))
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { selectCustomerLabel; Spacer(); addCustomerButton }
                    VStack(alignment: .leading, spacing: 0) { selectCustomerLabel; addCustomerButton }
                }
                if rows.isEmpty {
                    EmptyState(title: "No matches", message: "Try another search.", symbol: "magnifyingglass", action: ("Clear Filters", { query = "" }))
                }
                ForEach(rows) { c in
                    Button { draft.customer = c } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Space.s4) {
                                Text(c.fullName).font(.headline).foregroundStyle(Color.textPrimary)
                                Text(c.phone.isEmpty ? String(localized: "No phone") : Phone.display(c.phone)).font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: draft.customer?.id == c.id ? "checkmark" : "chevron.right")
                                .foregroundStyle(draft.customer?.id == c.id ? Color.brandSelected : Color.textSecondary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.customer?.id == c.id ? .isSelected : [])
                    .accessibilityIdentifier("rentro.new.customer.\(c.fullName)")
                }
            }
        }
        .sheet(isPresented: $adding) { CustomerFormView(business: business) { draft.customer = $0 } }
    }
}

// MARK: Step 2 · Device & schedule (S06)

private struct DeviceStep: View {
    @Environment(\.modelContext) private var context
    let business: Business
    @Bindable var draft: RentalDraft
    let next: () -> Void
    @Query private var devices: [RentalDevice]

    init(business: Business, draft: RentalDraft, next: @escaping () -> Void) {
        self.business = business
        self.draft = draft
        self.next = next
        let id = business.id
        _devices = Query(filter: #Predicate<RentalDevice> { $0.businessID == id }, sort: \.unitCode)
    }

    private var validPeriod: Bool { draft.returnAt > draft.pickupAt }
    private func conflict(_ d: RentalDevice) -> Bool {
        validPeriod && context.conflictingRental(device: d, from: draft.pickupAt, to: draft.returnAt, turnaroundMinutes: business.turnaroundMinutes) != nil
    }
    private var ready: Bool { validPeriod && draft.device.map { !conflict($0) } == true }

    var body: some View {
        let bookable = devices.filter { $0.lifecycle == .enabled }
        StepPage(title: "New Rental", subtitle: "Step 2 of 4 · Device & Schedule", primary: "Continue",
                 enabled: ready, id: "rentro.new.continue2", action: next) {
            VStack(spacing: Space.s8) {
                DatePicker("Pickup", selection: $draft.pickupAt, in: Date.now.addingTimeInterval(-300)...)
                DatePicker("Return", selection: $draft.returnAt, in: draft.pickupAt...)
            }
            .environment(\.timeZone, business.timeZone)
            .foregroundStyle(Color.textPrimary)
            .tint(.brandSelected)
            .card()
            if !validPeriod {
                Text("Return must be after pickup.").font(.footnote).foregroundStyle(Color.textDanger)
            } else if let q = draft.quote {
                Text("\(billableDays(q.billableUnits)) · \(q.subtotalIDR.rupiah) · \(business.timeZone.identifier)")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
            }
            Text("AVAILABLE DEVICES").font(.caption).foregroundStyle(Color.textSecondary)
            if bookable.isEmpty {
                EmptyState(title: "No devices yet", message: "Add your first rental iPhone to get started.", symbol: "iphone")
            }
            ForEach(bookable) { d in
                let blocked = conflict(d)
                Button { draft.device = d } label: {
                    HStack(spacing: Space.s12) {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text("\(d.model) · \(d.unitCode)").font(.headline).foregroundStyle(Color.textPrimary)
                            Text(blocked ? "This iPhone is already booked for these dates." : "\(d.capacityGB)GB · \(d.dailyRateIDR.rupiah) / day")
                                .font(.footnote).foregroundStyle(blocked ? Color.textDanger : Color.textSecondary)
                        }
                        Spacer()
                        if blocked { StatusPill(text: String(localized: "Booked"), tone: .danger) }
                        else if draft.device?.id == d.id { Image(systemName: "checkmark").foregroundStyle(Color.brandSelected) }
                    }
                    .card()
                    .opacity(blocked ? 0.6 : 1)
                }
                .buttonStyle(.plain)
                .disabled(blocked)
                .accessibilityAddTraits(draft.device?.id == d.id ? .isSelected : [])
                .accessibilityIdentifier("rentro.new.device.\(d.unitCode)")
            }
        }
    }
}

// MARK: Step 3 · Price & payment (S07)

private struct PriceStep: View {
    let business: Business
    @Bindable var draft: RentalDraft
    let next: () -> Void

    private var rate: Int { draft.device?.dailyRateIDR ?? 0 }
    private var deposit: Int { draft.device?.depositIDR ?? 0 }
    private var subtotal: Int { draft.quote?.subtotalIDR ?? 0 }
    private var total: Int { subtotal - draft.discount }
    private var error: String? {
        if draft.discount < 0 || draft.discount > subtotal { return "Discount must be between Rp 0 and the subtotal." }
        if draft.paidNow < 0 || draft.paidNow > total { return String(localized: "Paid now cannot exceed the rental total.") }
        return nil
    }

    var body: some View {
        StepPage(title: "New Rental", subtitle: "Step 3 of 4 · Price & Payment", primary: "Continue",
                 enabled: error == nil, id: "rentro.new.continue3", action: next) {
            SummaryCard(title: "Quote") {
                AlignedLabelValueRow(label: "Daily rate", value: rate.rupiah)
                Divider()
                AlignedLabelValueRow(label: LocalizedStringKey(billableDays(draft.quote?.billableUnits ?? 1)), value: subtotal.rupiah)
                if draft.discount > 0 { Divider(); AlignedLabelValueRow(label: "Discount", value: "-" + draft.discount.rupiah) }
                Divider()
                AlignedLabelValueRow(label: "Rental total", value: total.rupiah)
                Divider()
                AlignedLabelValueRow(label: "Security deposit (refundable)", value: deposit.rupiah)
            }
            RentroFormField(label: "Discount") { RupiahField(value: $draft.discount, id: "rentro.new.discount") }
            RentroFormField(label: "Paid now") { RupiahField(value: $draft.paidNow, id: "rentro.new.paid") }
            if deposit > 0 {
                Toggle("Deposit \(deposit.rupiah) collected now", isOn: $draft.depositNow).tint(.brandSelected)
                    .frame(minHeight: 44).foregroundStyle(Color.textPrimary)
            }
            RentroFormField(label: "Payment method") {
                Picker("Method", selection: $draft.method) {
                    ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden().tint(.textPrimary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
        }
    }
}

// MARK: Step 4 · Review (S08)

private struct ReviewStep: View {
    @Environment(\.modelContext) private var context
    let business: Business
    let draft: RentalDraft
    let changeSchedule: () -> Void
    let created: (Rental) -> Void
    @State private var error: DomainError?
    @State private var other: String?
    @State private var saving = false

    var body: some View {
        let tz = business.timeZone
        let subtotal = draft.quote?.subtotalIDR ?? 0
        StepPage(title: "Review Rental", subtitle: "Step 4 of 4 · Confirm", primary: saving ? "Confirming…" : "Confirm Rental",
                 enabled: !saving, id: "rentro.new.confirm", action: confirm) {
            SummaryCard(title: "Rental") {
                AlignedLabelValueRow(label: "Customer", value: draft.customer?.fullName ?? "-")
                Divider()
                AlignedLabelValueRow(label: "Device", value: "\(draft.device?.model ?? "-") · \(draft.device?.unitCode ?? "-")")
                Divider()
                AlignedLabelValueRow(label: "Pickup", value: draft.pickupAt.stamp(tz))
                Divider()
                AlignedLabelValueRow(label: "Return", value: draft.returnAt.stamp(tz))
            }
            SummaryCard(title: "Payment") {
                AlignedLabelValueRow(label: "Rental fee", value: (subtotal - draft.discount).rupiah)
                Divider()
                AlignedLabelValueRow(label: "Deposit", value: (draft.device?.depositIDR ?? 0).rupiah)
                Divider()
                AlignedLabelValueRow(label: "Paid now", value: (draft.paidNow + (draft.depositNow ? draft.device?.depositIDR ?? 0 : 0)).rupiah)
            }
            Text("By confirming, staff acknowledge the rental policy and tracking disclosure where applicable.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
            if error == .conflict {
                Text(DomainError.conflict.localizedDescription).font(.footnote).foregroundStyle(Color.textDanger)
                Button("Change Device/Time", action: changeSchedule).frame(minHeight: 44).foregroundStyle(Color.textAccent)
            } else if let other {
                Text(other).font(.footnote).foregroundStyle(Color.textDanger)
            }
        }
    }

    private func confirm() {
        guard let customer = draft.customer, let device = draft.device else { return }
        saving = true
        defer { saving = false }
        do {
            let r = try context.createRental(business: business, RentalInput(
                customer: customer, device: device, pickupAt: draft.pickupAt, expectedReturnAt: draft.returnAt,
                discountIDR: draft.discount, initialPaymentIDR: draft.paidNow,
                depositPaidIDR: draft.depositNow ? device.depositIDR : 0, method: draft.method, idempotencyKey: draft.key))
            created(r)
        } catch let e as DomainError { error = e; other = e == .conflict ? nil : e.localizedDescription }
        catch { other = error.localizedDescription }
    }
}

private struct DoneStep: View {
    let rental: Rental?
    let done: () -> Void
    let view: (Bool) -> Void
    var body: some View {
        VStack(spacing: Space.s16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Color.brandSelected).accessibilityHidden(true)
            Text("Rental confirmed").font(.title2.bold()).foregroundStyle(Color.textPrimary)
            Text(rental?.code ?? "").foregroundStyle(Color.textSecondary)
            Spacer()
            Button("View Rental") { view(false) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rentro.new.view")
            Button("Start Pickup") { view(true) }.frame(minHeight: 44).foregroundStyle(Color.textAccent)
            Button("Done", action: done).frame(minHeight: 44).foregroundStyle(Color.textSecondary)
        }
        .padding(Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }
}
