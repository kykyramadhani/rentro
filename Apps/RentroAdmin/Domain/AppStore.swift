import SwiftData
import SwiftUI

enum AppTab: Hashable { case home, rentals, devices, map, settings }
enum Appearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    /// Localised name for display; `rawValue` stays the stable stored key.
    var title: String {
        switch self { case .system: String(localized: "System"); case .light: String(localized: "Light"); case .dark: String(localized: "Dark") }
    }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

/// UI-only state (selected tab, list filters). Data lives in SwiftData; views read it with @Query.
@MainActor @Observable
final class AppStore {
    var tab: AppTab = .home
    var rentalFilter: RentalFilter = .all
    var rentalQuery = ""
    var deviceFilter: DeviceFilter = .all
    var deviceQuery = ""
    var addingDevice = false
    var newRentalPresented = false
    /// Set by the wizard's success screen; RentalsView opens it, optionally straight into pickup.
    var selectedRental: Rental?
    var startPickupOnOpen = false
    var preselectedCustomer: Customer?
    /// Device Detail → "View location": the Map tab selects and centres this unit once.
    var mapFocus: UUID?

    func show(rentals filter: RentalFilter) { rentalFilter = filter; rentalQuery = ""; tab = .rentals }
    func show(devices filter: DeviceFilter) { deviceFilter = filter; deviceQuery = ""; tab = .devices }
}
