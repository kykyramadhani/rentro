import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FleetSharingController.self) private var fleet
    let business: Business
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Hero(title: "Settings", subtitle: "\(business.name) · Owner")
                List {
                    section("Business") {
                        NavigationLink { BusinessProfileView(business: business) } label: { row("Business Profile", detail: business.name) }
                            .accessibilityIdentifier("rentro.settings.profile")
                        NavigationLink { PoliciesView(business: business) } label: { row("Rental Rates & Policies") }
                            .accessibilityIdentifier("rentro.settings.policies")
                    }
                    section("Preferences") {
                        NavigationLink { AppearanceView() } label: { row("Appearance", detail: appearance.title) }
                            .accessibilityIdentifier("rentro.settings.appearance")
                        NavigationLink { NotificationsView() } label: { row("Notifications") }
                            .accessibilityIdentifier("rentro.settings.notifications")
                    }
                    section("Management") {
                        link("Team & Permissions", detail: String(localized: "Coming later"), symbol: "person.2")
                        NavigationLink { FleetSharingView() } label: { row("Tracker Sync", detail: fleet.summary) }
                            .accessibilityIdentifier("rentro.settings.fleet")
                        NavigationLink { PrivacyView() } label: { row("Privacy & Data") }
                            .accessibilityIdentifier("rentro.settings.privacy")
                    }
                    section("Help") {
                        NavigationLink { AboutView() } label: { row("About & Support") }.accessibilityIdentifier("rentro.settings.about")
                    }
                    section(nil) {
                        Button("Sign Out", role: .destructive) { confirmSignOut = true }
                            .accessibilityIdentifier("rentro.settings.signout")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color.bgCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Sign out of Rentro?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
            }
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey?, @ViewBuilder _ content: () -> C) -> some View {
        Section {
            content()
        } header: {
            if let title { Text(title).textCase(.uppercase).font(.caption).foregroundStyle(Color.textSecondary) }
        }
        .listRowBackground(Color.bgSurface)
    }

    private func row(_ title: LocalizedStringKey, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(title).foregroundStyle(Color.textPrimary)
            if let detail { Text(detail).font(.caption).foregroundStyle(Color.textSecondary) }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    private func link(_ title: LocalizedStringKey, detail: String? = nil, symbol: String) -> some View {
        NavigationLink { SettingsPlaceholder(title: title, symbol: symbol) } label: { row(title, detail: detail) }
    }
}

struct AppearanceView: View {
    @AppStorage("appearance") private var appearance = Appearance.system

    var body: some View {
        List {
            Section {
                ForEach(Appearance.allCases, id: \.self) { a in
                    Button { appearance = a } label: {
                        HStack {
                            Text(a.title).foregroundStyle(Color.textPrimary)
                            Spacer()
                            if a == appearance { Image(systemName: "checkmark").foregroundStyle(Color.brandSelected) }
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityAddTraits(a == appearance ? .isSelected : [])
                    .accessibilityIdentifier("rentro.appearance.\(a.rawValue.lowercased())")
                }
            } footer: { Text("System follows your iPhone's appearance setting.") }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bgCanvas)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Phase B screens (S29, S30, S32–S35); labelled, not a dead row.
struct SettingsPlaceholder: View {
    let title: LocalizedStringKey
    let symbol: String
    var body: some View {
        EmptyState(title: title, message: "Coming later.", symbol: symbol)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .background(Color.bgCanvas)
    }
}
