import SwiftData
import SwiftUI

private enum RentalSheet: String, Identifiable {
    case pickup, returnIt, extend, cancel, pay, deposit
    var id: String { rawValue }
}

/// S09 Rental Detail. Figma 44:640 / 44:1351. Buttons follow the lifecycle: nothing for a terminal state is offered twice.
struct RentalDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let rental: Rental
    let business: Business
    @State private var sheet: RentalSheet?
    @State private var confirmCall = false

    var body: some View {
        let tz = business.timeZone
        let badge = rental.badge(now: .now, calendar: business.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                HStack { Spacer(); StatusPill(text: badge.title, tone: badge.tone) }
                SummaryCard(title: "Customer") {
                    HStack {
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text(rental.customerName).font(.headline).foregroundStyle(Color.textPrimary)
                            if let phone = rental.customer?.phone, !phone.isEmpty {
                                Text(Phone.display(phone)).font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                        if let phone = rental.customer?.phone, !phone.isEmpty {
                            Button { confirmCall = true } label: { Image(systemName: "phone").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel("Call \(rental.customerName)")
                                .confirmationDialog("Call \(Phone.display(phone))?", isPresented: $confirmCall, titleVisibility: .visible) {
                                    Button("Call") { openURL(URL(string: "tel:\(phone)")!) }
                                }
                        }
                    }
                }
                SummaryCard(title: "Device") {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Text("\(rental.deviceModel) · \(rental.unitCode)").font(.headline).foregroundStyle(Color.textPrimary)
                        if let d = rental.device { Text("\(d.capacityGB)GB" + (d.color.isEmpty ? "" : " · \(d.color)")).font(.footnote).foregroundStyle(Color.textSecondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                SummaryCard(title: "Schedule · \(tz.identifier)") {
                    AlignedLabelValueRow(label: "Pickup", value: rental.pickupAt.stamp(tz))
                    if let a = rental.actualPickupAt { Divider(); AlignedLabelValueRow(label: "Picked up", value: a.stamp(tz)) }
                    Divider()
                    AlignedLabelValueRow(label: "Return", value: rental.expectedReturnAt.stamp(tz))
                    if let a = rental.actualReturnAt { Divider(); AlignedLabelValueRow(label: "Returned", value: a.stamp(tz)) }
                }
                SummaryCard(title: "Balance") {
                    AlignedLabelValueRow(label: "Rental total", value: rental.totalChargesIDR.rupiah)
                    if rental.lateFeeIDR > 0 { Divider(); AlignedLabelValueRow(label: "Includes late fee", value: rental.lateFeeIDR.rupiah) }
                    Divider()
                    AlignedLabelValueRow(label: "Paid", value: rental.amountPaidIDR.rupiah)
                    Divider()
                    AlignedLabelValueRow(label: rental.balanceDueIDR < 0 ? "Overpaid" : "Outstanding", value: abs(rental.balanceDueIDR).rupiah)
                }
                SummaryCard(title: "Deposit") {
                    AlignedLabelValueRow(label: "Required", value: rental.depositIDR.rupiah)
                    Divider()
                    AlignedLabelValueRow(label: "Held (refundable)", value: rental.depositHeldIDR.rupiah)
                }
                let entries = (rental.payments ?? []).sorted { $0.createdAt < $1.createdAt }
                if !entries.isEmpty {
                    SummaryCard(title: "Payments") {
                        ForEach(entries) { e in
                            AlignedLabelValueRow(label: "\(e.category.title) · \(e.method.title)", value: e.amountIDR.rupiah)
                        }
                    }
                }
                let events = (rental.events ?? []).sorted { $0.createdAt < $1.createdAt }
                SummaryCard(title: "Timeline") {
                    ForEach(events) { ev in
                        AlignedLabelValueRow(label: LocalizedStringKey(ev.title + (ev.note.isEmpty ? "" : " · \(ev.note)")), value: ev.createdAt.stamp(tz))
                    }
                }
                actions
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle(rental.code)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { s in
            switch s {
            case .pickup: PickupSheet(rental: rental, business: business)
            case .returnIt: ReturnSheet(rental: rental, business: business)
            case .extend: ExtendSheet(rental: rental, business: business)
            case .cancel: CancelSheet(rental: rental)
            case .pay: PaymentSheet(rental: rental, business: business)
            case .deposit: DepositSheet(rental: rental)
            }
        }
        .onAppear {
            if store.startPickupOnOpen, rental.status == .reserved { sheet = .pickup }
            store.startPickupOnOpen = false
            store.selectedRental = nil
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: Space.s8) {
            switch rental.status {
            case .reserved: primary("Start Pickup", .pickup, "rentro.detail.pickup")
            case .active: primary("Return Device", .returnIt, "rentro.detail.return")
            default: EmptyView()
            }
            if rental.status != .cancelled { secondary("Record Payment", .pay, "rentro.detail.pay") }
            if rental.status == .active { secondary("Extend Rental", .extend, "rentro.detail.extend") }
            if (rental.status == .completed || rental.status == .cancelled), rental.depositHeldIDR > 0 {
                secondary("Settle Deposit", .deposit, "rentro.detail.deposit")
            }
            if rental.status == .reserved {
                Button("Cancel Reservation", role: .destructive) { sheet = .cancel }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("rentro.detail.cancel")
            }
        }
    }

    private func primary(_ t: LocalizedStringKey, _ s: RentalSheet, _ id: String) -> some View {
        Button(t) { sheet = s }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier(id)
    }
    private func secondary(_ t: LocalizedStringKey, _ s: RentalSheet, _ id: String) -> some View {
        Button(t) { sheet = s }.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(Color.textAccent).accessibilityIdentifier(id)
    }
}

extension PaymentCategory {
    var title: String {
        switch self {
        case .rentalPayment: String(localized: "Rental payment")
        case .depositReceived: String(localized: "Deposit received")
        case .depositRefunded: String(localized: "Deposit refunded")
        case .depositDeduction: String(localized: "Deposit deduction")
        case .adjustment: String(localized: "Adjustment")
        }
    }
}

// MARK: shared scaffold

private struct ActionSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let primary: LocalizedStringKey
    var destructive = false
    var enabled = true
    var error: String?
    var id: String
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    content
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                    Button(primary, role: destructive ? .destructive : nil, action: action)
                        .buttonStyle(PrimaryButtonStyle()).tint(destructive ? Color.textDanger : nil)
                        .disabled(!enabled).accessibilityIdentifier(id)
                }
                .padding(Space.s20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: S10 Pickup

private struct PickupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    let business: Business
    @State private var checks = ["Screen": true, "Cameras": true, "Battery": true, "Accessories": true]   // stable keys; shown via checkLabel
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        let tz = business.timeZone
        ActionSheet(title: "Pickup", primary: "Confirm Handover", error: error, id: "rentro.pickup.confirm", action: confirm) {
            SummaryCard(title: "Handover") {
                AlignedLabelValueRow(label: "Customer", value: rental.customerName)
                Divider()
                AlignedLabelValueRow(label: "Device", value: "\(rental.deviceModel) · \(rental.unitCode)")
                Divider()
                AlignedLabelValueRow(label: "Planned pickup", value: rental.pickupAt.stamp(tz))
                Divider()
                AlignedLabelValueRow(label: "Actual pickup", value: Date.now.stamp(tz))
            }
            SummaryCard(title: "Condition checklist") {
                ForEach(["Screen", "Cameras", "Battery", "Accessories"], id: \.self) { k in
                    Toggle(checkLabel(k), isOn: Binding(get: { checks[k] ?? false }, set: { checks[k] = $0 })).tint(.brandSelected)
                        .frame(minHeight: 44).foregroundStyle(Color.textPrimary)
                }
            }
            RentroFormField(label: "Condition notes (optional)") { TextField("Scratches, accessories handed over…", text: $notes) }
        }
    }

    private func checkLabel(_ k: String) -> String {
        switch k {
        case "Screen": String(localized: "Screen")
        case "Cameras": String(localized: "Cameras")
        case "Battery": String(localized: "Battery")
        default: String(localized: "Accessories")
        }
    }

    private func confirm() {
        let issues = checks.filter { !$0.value }.keys.sorted().map { String(localized: "\(checkLabel($0)) not OK") }
        let note = ([notes] + issues).filter { !$0.isEmpty }.joined(separator: "; ")
        do { try context.confirmPickup(rental, note: note); dismiss() } catch { self.error = error.localizedDescription }
    }
}

// MARK: S11 Return

private struct ReturnSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    let business: Business
    @State private var at = Date.now
    @State private var damage = 0
    @State private var reason = ""
    @State private var condition = ""
    @State private var needsMaintenance = false
    @State private var error: String?

    private var late: Int {
        Billing.lateFee(dailyRateIDR: rental.dailyRateIDR, expectedReturn: rental.expectedReturnAt, actualReturn: at,
                        graceMinutes: rental.lateGraceMinutes, unit: rental.lateFeeUnit, amountIDR: rental.lateFeeAmountIDR)
    }
    private var total: Int { rental.subtotalIDR - rental.discountIDR + late + max(damage, 0) }

    var body: some View {
        ActionSheet(title: "Return", primary: "Confirm Return", error: error, id: "rentro.return.confirm", action: confirm) {
            DatePicker("Actual return", selection: $at).environment(\.timeZone, business.timeZone).tint(.brandSelected)
                .foregroundStyle(Color.textPrimary).card()
            RentroFormField(label: "Damage charge (optional)") { RupiahField(value: $damage, id: "rentro.return.damage") }
            RentroFormField(label: "Condition notes (optional)") {
                TextField("Scratches, accessories returned…", text: $condition).accessibilityIdentifier("rentro.return.condition")
            }
            Toggle("Needs maintenance before the next rental", isOn: $needsMaintenance).tint(.brandSelected)
                .frame(minHeight: 44).foregroundStyle(Color.textPrimary).accessibilityIdentifier("rentro.return.maintenance")
            if damage > 0 { RentroFormField(label: "Reason for damage charge") { TextField("Cracked screen", text: $reason).accessibilityIdentifier("rentro.return.reason") } }
            SummaryCard(title: "Settlement") {
                AlignedLabelValueRow(label: "Rental", value: (rental.subtotalIDR - rental.discountIDR).rupiah)
                Divider()
                AlignedLabelValueRow(label: "Late fee", value: late.rupiah)
                Divider()
                AlignedLabelValueRow(label: "Damage", value: max(damage, 0).rupiah)
                Divider()
                AlignedLabelValueRow(label: "Paid", value: rental.amountPaidIDR.rupiah)
                Divider()
                AlignedLabelValueRow(label: "Outstanding", value: (total - rental.amountPaidIDR).rupiah)
                Divider()
                AlignedLabelValueRow(label: "Deposit held", value: rental.depositHeldIDR.rupiah)
            }
            Text("Late fee follows the policy this rental was booked under. The deposit stays held until you settle it.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
        }
    }

    private func checkLabel(_ k: String) -> String {
        switch k {
        case "Screen": String(localized: "Screen")
        case "Cameras": String(localized: "Cameras")
        case "Battery": String(localized: "Battery")
        default: String(localized: "Accessories")
        }
    }

    private func confirm() {
        do { try context.confirmReturn(rental, business: business, at: at, damageFeeIDR: damage, damageReason: reason,
                                         conditionNote: condition, needsMaintenance: needsMaintenance); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: S12 Extend

private struct ExtendSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    let business: Business
    @State private var newReturn: Date
    @State private var error: String?

    init(rental: Rental, business: Business) {
        self.rental = rental
        self.business = business
        _newReturn = State(initialValue: rental.expectedReturnAt.addingTimeInterval(86400))
    }

    private var units: Int { Billing.billableDays(from: rental.pickupAt, to: newReturn) }
    private var conflict: Bool {
        guard let d = rental.device, newReturn > rental.expectedReturnAt else { return false }
        return context.conflictingRental(device: d, from: rental.pickupAt, to: newReturn, turnaroundMinutes: business.turnaroundMinutes, excluding: rental.id) != nil
    }

    var body: some View {
        let tz = business.timeZone
        ActionSheet(title: "Extend Rental", primary: "Confirm Extension", enabled: newReturn > rental.expectedReturnAt && !conflict,
                    error: conflict ? DomainError.conflict.localizedDescription : error, id: "rentro.extend.confirm", action: confirm) {
            SummaryCard(title: "Return") {
                AlignedLabelValueRow(label: "Current", value: rental.expectedReturnAt.stamp(tz))
                Divider()
                AlignedLabelValueRow(label: "Added days", value: "\(max(units - rental.billableUnits, 0))")
                Divider()
                AlignedLabelValueRow(label: "Added charge", value: max(units - rental.billableUnits, 0) * rental.dailyRateIDR == 0 ? "Rp 0" : (max(units - rental.billableUnits, 0) * rental.dailyRateIDR).rupiah)
            }
            DatePicker("New return", selection: $newReturn, in: rental.expectedReturnAt...).environment(\.timeZone, tz).tint(.brandSelected)
                .foregroundStyle(Color.textPrimary).card()
        }
    }

    private func checkLabel(_ k: String) -> String {
        switch k {
        case "Screen": String(localized: "Screen")
        case "Cameras": String(localized: "Cameras")
        case "Battery": String(localized: "Battery")
        default: String(localized: "Accessories")
        }
    }

    private func confirm() {
        do { try context.extendRental(rental, business: business, to: newReturn); dismiss() } catch { self.error = error.localizedDescription }
    }
}

// MARK: S13 Cancel

private struct CancelSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    @State private var reason = ""
    @State private var confirm = false
    @State private var error: String?

    var body: some View {
        ActionSheet(title: "Cancel Reservation", primary: "Cancel Reservation", destructive: true,
                    enabled: !reason.trimmingCharacters(in: .whitespaces).isEmpty, error: error, id: "rentro.cancel.confirm",
                    action: { confirm = true }) {
            RentroFormField(label: "Reason") { TextField("Customer changed plans", text: $reason).accessibilityIdentifier("rentro.cancel.reason") }
            Text(rental.depositHeldIDR > 0
                 ? "\(rental.depositHeldIDR.rupiah) deposit is held. Refund it with Settle Deposit after cancelling."
                 : "No deposit is held. The booking and its history stay on record.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .confirmationDialog("Cancel \(rental.code)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Cancel Reservation", role: .destructive) {
                do { try context.cancelReservation(rental, reason: reason); dismiss() } catch { self.error = error.localizedDescription }
            }
            Button("Keep Reservation", role: .cancel) {}
        }
    }
}

// MARK: S25 Record Payment

private struct PaymentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    let business: Business
    @State private var amount: Int
    @State private var method = PaymentMethod.cash
    @State private var reference = ""
    @State private var paidAt = Date.now
    @State private var key = UUID().uuidString
    @State private var error: String?
    @State private var askOverpay = false

    init(rental: Rental, business: Business) {
        self.rental = rental
        self.business = business
        _amount = State(initialValue: max(rental.balanceDueIDR, 0))
    }

    var body: some View {
        ActionSheet(title: "Record Payment", primary: "Save Payment", error: error, id: "rentro.pay.save", action: { save(false) }) {
            SummaryCard(title: LocalizedStringKey(rental.code)) {
                AlignedLabelValueRow(label: "Outstanding", value: max(rental.balanceDueIDR, 0).rupiah)
            }
            RentroFormField(label: "Amount") { RupiahField(value: $amount, id: "rentro.pay.amount") }
            RentroFormField(label: "Method") {
                Picker("Method", selection: $method) { ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().tint(.textPrimary)
            }
            RentroFormField(label: "Reference (optional)") { TextField("Transfer reference", text: $reference) }
            DatePicker("Paid at", selection: $paidAt, in: ...Date.now).environment(\.timeZone, business.timeZone).tint(.brandSelected)
                .foregroundStyle(Color.textPrimary).card()
            Text("Manual bookkeeping only. Rentro does not verify bank transfers or e-wallet payments.").font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .alert("Record an overpayment?", isPresented: $askOverpay) {
            Button("Record Overpayment") { save(true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This is more than the balance due.") }
    }

    private func save(_ allow: Bool) {
        do { try context.recordPayment(rental, amountIDR: amount, method: method, reference: reference, paidAt: paidAt, key: key, allowOverpayment: allow); dismiss() }
        catch DomainError.overpayment { askOverpay = true }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: S26 Deposit Settlement

private struct DepositSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rental: Rental
    @State private var refund: Int
    @State private var deduction = 0
    @State private var reason = ""
    @State private var method = PaymentMethod.cash
    @State private var key = UUID().uuidString
    @State private var error: String?

    init(rental: Rental) {
        self.rental = rental
        _refund = State(initialValue: rental.depositHeldIDR)
    }

    var body: some View {
        ActionSheet(title: "Deposit Settlement", primary: "Confirm Settlement", error: error, id: "rentro.deposit.confirm", action: confirm) {
            SummaryCard(title: "Deposit") {
                AlignedLabelValueRow(label: "Held", value: rental.depositHeldIDR.rupiah)
                Divider()
                AlignedLabelValueRow(label: "Still held after", value: (rental.depositHeldIDR - refund - deduction).rupiah)
            }
            RentroFormField(label: "Refund to customer") { RupiahField(value: $refund, id: "rentro.deposit.refund") }
            RentroFormField(label: "Deduction") { RupiahField(value: $deduction, id: "rentro.deposit.deduction") }
            if deduction > 0 { RentroFormField(label: "Reason for deduction") { TextField("Replaced charger", text: $reason).accessibilityIdentifier("rentro.deposit.reason") } }
            RentroFormField(label: "Method") {
                Picker("Method", selection: $method) { ForEach(PaymentMethod.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().tint(.textPrimary)
            }
            Text("The deposit is a refundable liability. Settling it does not change rental income.").font(.footnote).foregroundStyle(Color.textSecondary)
        }
    }

    private func checkLabel(_ k: String) -> String {
        switch k {
        case "Screen": String(localized: "Screen")
        case "Cameras": String(localized: "Cameras")
        case "Battery": String(localized: "Battery")
        default: String(localized: "Accessories")
        }
    }

    private func confirm() {
        do { try context.settleDeposit(rental, refundIDR: refund, deductionIDR: deduction, reason: reason, method: method, key: key); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
