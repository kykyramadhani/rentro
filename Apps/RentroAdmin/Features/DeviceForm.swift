import SwiftData
import SwiftUI

/// S16 Add / Edit Device. Figma 44:851 / 44:1562.
struct DeviceFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let business: Business
    var device: RentalDevice?

    @State private var input = DeviceInput()
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s16) {
                    RentroFormField(label: "Unit code") {
                        TextField("IP-021", text: $input.unitCode)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .accessibilityIdentifier("rentro.device.unitcode")
                    }
                    RentroFormField(label: "Model") {
                        TextField("iPhone 15 Pro", text: $input.model).accessibilityIdentifier("rentro.device.model")
                    }
                    RentroFormField(label: "Capacity") {
                        Picker("Capacity", selection: $input.capacityGB) {
                            ForEach([64, 128, 256, 512, 1024], id: \.self) { Text($0 == 1024 ? "1TB" : "\($0)GB").tag($0) }
                        }
                        .labelsHidden().tint(.textPrimary)
                    }
                    RentroFormField(label: "Color (optional)") { TextField("Natural Titanium", text: $input.color) }
                    RentroFormField(label: "Serial / IMEI (optional)") {
                        TextField("Restricted to authorized staff", text: $input.serial).autocorrectionDisabled()
                    }
                    RentroFormField(label: "Daily rate") { RupiahField(value: $input.dailyRateIDR, id: "rentro.device.rate") }
                    RentroFormField(label: "Security deposit") { RupiahField(value: $input.depositIDR, id: "rentro.device.deposit") }
                    if device != nil {
                        Toggle("Active in inventory", isOn: $input.isActive).tint(.brandSelected)
                            .frame(minHeight: 44).foregroundStyle(Color.textPrimary)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.textDanger) }
                    Button("Save Device", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("rentro.device.save")
                }
                .padding(Space.s20)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.bgCanvas.ignoresSafeArea())
            .navigationTitle(device == nil ? "Add Device" : "Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = device {
            input = DeviceInput(unitCode: d.unitCode, model: d.model, color: d.color, serial: d.serial, capacityGB: d.capacityGB,
                                dailyRateIDR: d.dailyRateIDR, depositIDR: d.depositIDR, isActive: d.lifecycle != .retired)
        } else {
            input.dailyRateIDR = business.defaultDailyRateIDR
            input.depositIDR = business.defaultDepositIDR
        }
    }

    private func save() {
        do { try context.saveDevice(device, businessID: business.id, input); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
