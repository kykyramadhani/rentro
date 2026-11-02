import SwiftData
import SwiftUI
import UserNotifications

private struct SettingsPage<Content: View>: View {
    let title: LocalizedStringKey
    var error: String?
    var primary: LocalizedStringKey?
    var id = ""
    var action: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                content
                if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                if let primary { Button(primary, action: action).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier(id) }
            }
            .padding(Space.s20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgCanvas.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IntField: View {
    @Binding var value: Int
    var suffix: LocalizedStringKey
    var id: String
    var body: some View {
        HStack(spacing: Space.s8) {
            TextField("0", value: $value, format: .number.grouping(.never)).keyboardType(.numberPad).accessibilityIdentifier(id)
            Text(suffix).foregroundStyle(Color.textSecondary)
        }
        .foregroundStyle(Color.textPrimary)
    }
}

// MARK: S29 Business Profile. Figma 43:4487 / 43:4851

struct BusinessProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let business: Business
    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var wilayahKode = ""
    @State private var tz = ""
    @State private var error: String?
    @State private var confirmTZ = false
    @State private var loaded = false

    var body: some View {
        SettingsPage(title: "Business Profile", error: error, primary: "Save", id: "rentro.profile.save", action: save) {
            RentroFormField(label: "Business name") { TextField("Business name", text: $name).accessibilityIdentifier("rentro.profile.name") }
            RentroFormField(label: "Phone") { TextField("+62 …", text: $phone).keyboardType(.phonePad) }
            RentroFormField(label: "Address") { TextField("Street, building", text: $address) }
            WilayahPicker(kode: $wilayahKode)
            RentroFormField(label: "Timezone") {
                Picker("Timezone", selection: $tz) { ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) } }.labelsHidden().tint(.textPrimary)
            }
            RentroFormField(label: "Currency") { Text("IDR (Indonesian Rupiah)").foregroundStyle(Color.textSecondary) }
        }
        .confirmationDialog("Change timezone to \(tz)?", isPresented: $confirmTZ, titleVisibility: .visible) {
            Button("Change Timezone") { apply() }
        } message: { Text("Times shown in the app will shift. Stored rental times do not change.") }
        .onAppear {
            guard !loaded else { return }
            loaded = true; name = business.name; phone = business.phone; address = business.address; wilayahKode = business.wilayahKode; tz = business.timeZoneID
        }
    }

    private func save() { if tz != business.timeZoneID { confirmTZ = true } else { apply() } }

    private func apply() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { error = "Enter your business name."; return }
        guard TimeZone(identifier: tz) != nil else { error = "Choose a valid timezone."; return }
        business.name = n
        business.phone = phone.trimmingCharacters(in: .whitespaces)
        business.address = address.trimmingCharacters(in: .whitespaces)
        business.wilayahKode = wilayahKode
        business.timeZoneID = tz                 // display only: stored instants are absolute Dates (AT-27)
        do { try context.save(); dismiss() } catch { self.error = error.localizedDescription }
    }
}

// MARK: S30 Rental Rates & Policies. Figma 43:4521 / 43:4885

struct PoliciesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let business: Business
    @State private var rate = 0
    @State private var deposit = 0
    @State private var grace = 0
    @State private var lateUnit = LateFeeUnit.day
    @State private var lateAmount = 0
    @State private var turnaround = 0
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        let sample = Billing.quote(dailyRateIDR: rate, from: .now, to: .now.addingTimeInterval(2 * 86400 + 60))
        SettingsPage(title: "Rates & Policies", error: error, primary: "Save", id: "rentro.policies.save", action: save) {
            RentroFormField(label: "Default daily rate") { RupiahField(value: $rate, id: "rentro.policies.rate") }
            RentroFormField(label: "Default security deposit") { RupiahField(value: $deposit, id: "rentro.policies.deposit") }
            RentroFormField(label: "Minimum charge") { Text("1 day").foregroundStyle(Color.textPrimary) }
            RentroFormField(label: "Late-fee grace period") { IntField(value: $grace, suffix: "minutes", id: "rentro.policies.grace") }
            RentroFormField(label: "Late fee charged") {
                Picker("Late fee charged", selection: $lateUnit) {
                    ForEach(LateFeeUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("rentro.policies.lateunit")
            }
            RentroFormField(label: "Late-fee amount (0 = use the device rate)") { RupiahField(value: $lateAmount, id: "rentro.policies.lateamount") }
            RentroFormField(label: "Turnaround buffer between rentals") { IntField(value: $turnaround, suffix: "minutes", id: "rentro.policies.turnaround") }
            SummaryCard(title: "Sample quote") {
                AlignedLabelValueRow(label: "2 days and 1 minute", value: "\(sample.billableUnits) billable days")
                Divider()
                AlignedLabelValueRow(label: "Rental total", value: sample.subtotalIDR.rupiah)
            }
            Text("New bookings use these values. Existing bookings keep the rate and deposit they were booked with. A late fee is charged for every started day or hour after the grace period.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true; rate = business.defaultDailyRateIDR; deposit = business.defaultDepositIDR
            grace = business.lateGraceMinutes; turnaround = business.turnaroundMinutes
            lateUnit = business.lateFeeUnit; lateAmount = business.lateFeeAmountIDR
        }
    }

    private func save() {
        guard rate >= 0, deposit >= 0, grace >= 0, turnaround >= 0, lateAmount >= 0 else { error = String(localized: "Values cannot be negative."); return }
        business.defaultDailyRateIDR = rate; business.defaultDepositIDR = deposit
        business.lateGraceMinutes = grace; business.turnaroundMinutes = turnaround
        business.lateFeeUnit = lateUnit; business.lateFeeAmountIDR = lateAmount
        do { try context.save(); dismiss() } catch { self.error = error.localizedDescription }
    }
}

// MARK: S32 Notifications. Figma 43:4591 / 43:4955

enum NotificationKeys {
    static let pickup = "notif.pickup", returned = "notif.return", overdue = "notif.overdue"
    static let pickupLead = "notif.pickupLead", returnLead = "notif.returnLead"
}

extension ReminderPrefs {
    init(defaults: UserDefaults = .standard) {
        func flag(_ k: String) -> Bool { defaults.object(forKey: k) as? Bool ?? true }
        self.init(pickup: flag(NotificationKeys.pickup), returned: flag(NotificationKeys.returned), overdue: flag(NotificationKeys.overdue),
                  pickupLeadMinutes: defaults.object(forKey: NotificationKeys.pickupLead) as? Int ?? 24 * 60,
                  returnLeadMinutes: defaults.object(forKey: NotificationKeys.returnLead) as? Int ?? 120)
    }
}

struct NotificationsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(NotificationKeys.pickup) private var pickup = true
    @AppStorage(NotificationKeys.returned) private var returned = true
    @AppStorage(NotificationKeys.overdue) private var overdue = true
    @AppStorage(NotificationKeys.pickupLead) private var pickupLead = 24 * 60
    @AppStorage(NotificationKeys.returnLead) private var returnLead = 120
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        SettingsPage(title: "Notifications") {
            SummaryCard(title: "Permission") {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(statusTitle).font(.headline).foregroundStyle(Color.textPrimary).accessibilityIdentifier("rentro.notifications.status")
                    Text(status == .denied ? "Turned off in iOS Settings" : "Managed by iOS Settings").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if status == .notDetermined {
                    Button("Allow Notifications") { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await refresh() } }
                        .frame(minHeight: 44).foregroundStyle(Color.textAccent).accessibilityIdentifier("rentro.notifications.allow")
                } else if status == .denied {
                    Button("Open iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                        .frame(minHeight: 44).foregroundStyle(Color.textAccent).accessibilityIdentifier("rentro.notifications.settings")
                }
            }
            SummaryCard(title: "Rental alerts") {
                Toggle("Pickup reminders", isOn: $pickup).tint(.brandSelected).frame(minHeight: 44)
                if pickup { leadPicker("Remind me", $pickupLead, [30, 60, 120, 24 * 60]) }
                Divider()
                Toggle("Return reminders", isOn: $returned).tint(.brandSelected).frame(minHeight: 44)
                if returned { leadPicker("Remind me", $returnLead, [30, 60, 120]) }
                Divider()
                Toggle("Overdue alerts", isOn: $overdue).tint(.brandSelected).frame(minHeight: 44)
            }
            .foregroundStyle(Color.textPrimary)
            SummaryCard(title: "Device alerts") {
                Toggle("Tracking freshness alerts", isOn: .constant(false)).disabled(true).frame(minHeight: 44)
                Text("Available with the tracker feature. Coming later.").font(.footnote).foregroundStyle(Color.textSecondary)
            }
            Text("If permission is denied, Rentro still shows alerts inside the app.").font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await refresh() } } }   // back from iOS Settings
    }

    /// "1 day before", "2 hours before", "30 minutes before": explicit one/other keys so each language can word them.
    static func leadLabel(_ minutes: Int) -> LocalizedStringKey {
        if minutes >= 1440 { let d = minutes / 1440; return d == 1 ? "1 day before" : "\(d) days before" }
        if minutes >= 60 { let h = minutes / 60; return h == 1 ? "1 hour before" : "\(h) hours before" }
        return minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
    }

    private func leadPicker(_ label: LocalizedStringKey, _ value: Binding<Int>, _ options: [Int]) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            Picker(label, selection: value) {
                ForEach(options, id: \.self) { Text(Self.leadLabel($0)).tag($0) }
            }
            .labelsHidden().tint(.textAccent)
        }
        .frame(minHeight: 44)
    }

    private var statusTitle: String {
        switch status {
        case .authorized, .provisional, .ephemeral: String(localized: "Notifications allowed")
        case .denied: String(localized: "Notifications not allowed")
        default: String(localized: "Notifications not set up")
        }
    }

    private func refresh() async { status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}

// MARK: S34 Privacy & Data. Figma 43:4667 / 43:5031

struct PrivacyView: View {
    var body: some View {
        SettingsPage(title: "Privacy & Data") {
            SummaryCard(title: "What Rentro stores") {
                bullet("Customers", "Name and phone number you enter.")
                bullet("Devices", "Unit code, model, optional serial, rates.")
                bullet("Money", "Payments, deposits and refunds you record.")
                bullet("Locations", "None. No tracker is paired and nothing is collected.")
            }
            SummaryCard(title: "Where it lives") {
                Text("Your data is stored on this iPhone. Rentro works offline and does not need an account on a Rentro server. Signing in uses Sign in with Apple only to identify you.")
                    .font(.footnote).foregroundStyle(Color.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            SummaryCard(title: "Consent history") {
                Text("No consent records yet.").foregroundStyle(Color.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            SummaryCard(title: "Export and deletion") {
                Text("Export and deletion requests are coming later.").foregroundStyle(Color.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func bullet(_ t: LocalizedStringKey, _ d: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(t).foregroundStyle(Color.textPrimary)
            Text(d).font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: S35 About & Support. Figma 43:4712 / 43:5076

struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-" }

    var body: some View {
        SettingsPage(title: "About & Support") {
            SummaryCard(title: "Rentro") {
                AlignedLabelValueRow(label: "Version", value: version)
                Divider()
                AlignedLabelValueRow(label: "Build", value: build)
            }
            // TODO(owner): real support contact and Terms/Privacy URLs before release (PRD S35). Shown honestly as not configured.
            SummaryCard(title: "Support") {
                AlignedLabelValueRow(label: "Contact", value: String(localized: "Not configured"))
                Divider()
                AlignedLabelValueRow(label: "Terms", value: String(localized: "Not configured"))
                Divider()
                AlignedLabelValueRow(label: "Privacy Policy", value: String(localized: "Not configured"))
            }
            Text("Open Find My is a shortcut to Apple's website. Rentro does not read Find My data or location from your Apple Account.")
                .font(.footnote).foregroundStyle(Color.textSecondary)
        }
    }
}
