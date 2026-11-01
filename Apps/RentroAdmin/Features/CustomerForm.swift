import SwiftData
import SwiftUI

/// S23 Add / Edit Customer. Figma 44:1011 / 44:1722. Duplicates are allowed (no silent merge); the phone number disambiguates (AT-26).
struct CustomerFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let business: Business
    var customer: Customer?
    var onSaved: (Customer) -> Void = { _ in }

    @State private var name = ""
    @State private var phone = ""
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    RentroFormField(label: "Full name") {
                        TextField("Full name", text: $name).textContentType(.name).accessibilityIdentifier("rentro.customer.name")
                    }
                    RentroFormField(label: "Phone (optional)") {
                        TextField("0812 3456 7890", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                            .accessibilityIdentifier("rentro.customer.phone")
                    }
                    Text("Rentro stores this customer's name and phone on this device to manage rentals. No ID documents are collected.")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                    Button("Save Customer", action: save).buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("rentro.customer.save")
                }
                .padding(Space.s20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle(customer == nil ? "Add Customer" : "Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard !loaded, let c = customer else { return }
                loaded = true; name = c.fullName; phone = c.phone.isEmpty ? "" : Phone.display(c.phone)
            }
        }
    }

    private func save() {
        do {
            let c = try context.saveCustomer(customer, businessID: business.id, name: name, phone: phone)
            onSaved(c); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
