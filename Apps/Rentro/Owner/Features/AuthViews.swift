import AuthenticationServices
import SwiftData
import SwiftUI

/// S01. Figma 44:578 / 44:1289 minus email/password: PRD v2.0 makes Sign in with Apple the only auth.
/// First launch: the same app runs the business or tracks a rental iPhone. Changeable later (sign-in / pair screens).
struct RolePickerView: View {
    let choose: (DeviceRole) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s16) {
                RentroWordmark().padding(.top, Space.s24 * 2)
                Text("How will this iPhone be used?").font(.title2.bold()).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
                option(.owner, symbol: "storefront", title: "Run my rental business",
                       detail: "Manage rentals, devices, payments and the fleet map.")
                option(.tracker, symbol: "location.circle", title: "This is a rental iPhone",
                       detail: "Pair it with a rental business and share its location only with consent.")
                Text("You can change this later.").font(.footnote).foregroundStyle(Color.textSecondary)
            }
            .padding(Space.s20)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
    }

    private func option(_ role: DeviceRole, symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Button { choose(role) } label: {
            HStack(alignment: .top, spacing: Space.s12) {
                IconTile(symbol: symbol)
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(title).font(.headline).foregroundStyle(Color.textPrimary)
                    Text(detail).font(.subheadline).foregroundStyle(Color.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Color.textSecondary).accessibilityHidden(true)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rentro.role.\(role.rawValue)")
    }
}

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @AppStorage("deviceRole") private var role = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Spacer().frame(height: Space.s24 * 2)
            RentroWordmark()
            Text("Manage rentals and devices with less friction.")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
            Spacer().frame(height: Space.s24)
            SignInWithAppleButton(.signIn) { $0.requestedScopes = [] } onCompletion: { auth.handle($0) }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 48)
                .accessibilityIdentifier("rentro.signin.apple")
            if let message = auth.errorMessage {
                Text(message).font(.footnote).foregroundStyle(Color.textDanger).padding(.top, Space.s8)
            }
            Spacer()
            TextLinkButton("This is a rental iPhone instead") { role = "" }.accessibilityIdentifier("rentro.role.change")
            // TODO(owner): link real Terms/Privacy URLs before release (PRD S35).
            Text("By continuing, you agree to the Terms and Privacy Policy.")
                .font(.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Space.s20)
        .padding(.bottom, Space.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.bgCanvas.ignoresSafeArea())
    }
}

/// S02. Figma 44:606 / 44:1317. Saving creates the Business owned by the signed-in Apple user.
struct BusinessSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthStore.self) private var auth
    let userID: String

    @State private var input = BusinessInput()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    Text("Create your workspace before adding rental units.")
                        .font(.subheadline).foregroundStyle(Color.textSecondary)
                    RentroFormField(label: "Business name") {
                        TextField("Business name", text: $input.name)
                            .textContentType(.organizationName)
                            .accessibilityIdentifier("rentro.setup.name")
                    }
                    RentroFormField(label: "Phone (optional)") {
                        TextField("+62 …", text: $input.phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                    }
                    RentroFormField(label: "Timezone") {
                        Picker("Timezone", selection: $input.timeZoneID) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().tint(.textPrimary)
                    }
                    RentroFormField(label: "Default daily rate") {
                        RupiahField(value: $input.dailyRateIDR, id: "rentro.setup.rate")
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                    Button("Create Business", action: create)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("rentro.setup.create")
                }
                .padding(Space.s20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle("Business Setup")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Sign Out") { auth.signOut() } } }
        }
    }

    private func create() {
        do { try context.createBusiness(owner: userID, input) } catch { self.error = error.localizedDescription }
    }
}
