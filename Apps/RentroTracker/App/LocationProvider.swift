import CoreLocation
import Foundation

/// The only door to Core Location. The model never imports it, so tests drive it with a fake.
@MainActor protocol LocationProviding: AnyObject {
    var authorization: OSLocationAuth { get }
    var isPrecise: Bool { get }
    var onAuthChange: ((OSLocationAuth) -> Void)? { get set }
    var onSample: ((LocationSample) -> Void)? { get set }
    func requestWhenInUse()
    func requestAlways()
    func start(background: Bool)
    func stop()
    func requestOneShot()
}

/// Public Core Location only (PRD 4.6). Battery-aware: 50 m distance filter, system may pause updates.
@MainActor final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onAuthChange: ((OSLocationAuth) -> Void)?
    var onSample: ((LocationSample) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 50
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
    }

    var authorization: OSLocationAuth { Self.map(manager.authorizationStatus) }
    var isPrecise: Bool { manager.accuracyAuthorization == .fullAccuracy }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    /// Background delivery only with an explicit "Always" grant; the system's blue indicator stays visible to the renter.
    func start(background: Bool) {
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.startUpdatingLocation()
    }
    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
    func requestOneShot() { manager.requestLocation() }

    nonisolated static func map(_ s: CLAuthorizationStatus) -> OSLocationAuth {
        switch s {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let a = Self.map(m.authorizationStatus)
        Task { @MainActor in self.onAuthChange?(a) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.filter { $0.horizontalAccuracy >= 0 }.map {
            LocationSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                           horizontalAccuracyM: $0.horizontalAccuracy, measuredAt: $0.timestamp)
        }
        Task { @MainActor in samples.forEach { self.onSample?($0) } }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}   // a failed fix is a gap, never a fake point
}

#if DEBUG
/// Dev/test stand-in: no GPS, no OS prompt. Grants or denies on request and emits only what a test tells it to.
@MainActor final class FakeLocationProvider: LocationProviding {
    var authorization: OSLocationAuth
    var isPrecise = true
    var grantOnRequest: OSLocationAuth
    var onAuthChange: ((OSLocationAuth) -> Void)?
    var onSample: ((LocationSample) -> Void)?
    private(set) var started = false
    private(set) var startedInBackground = false
    private(set) var requests: [String] = []
    var oneShot: () -> LocationSample = { LocationSample(latitude: -8.65, longitude: 115.2167, horizontalAccuracyM: 12, measuredAt: .now) }

    init(authorization: OSLocationAuth = .notDetermined, grantOnRequest: OSLocationAuth = .whenInUse) {
        self.authorization = authorization
        self.grantOnRequest = grantOnRequest
    }
    func requestWhenInUse() {
        requests.append("whenInUse")
        guard authorization == .notDetermined else { return }       // iOS prompts once; later changes live in Settings
        authorization = grantOnRequest
        onAuthChange?(authorization)
    }
    func requestAlways() {
        requests.append("always")
        guard authorization == .whenInUse else { return }
        authorization = .always
        onAuthChange?(authorization)
    }
    func start(background: Bool) { started = true; startedInBackground = background }
    func stop() { started = false; startedInBackground = false }
    func requestOneShot() { onSample?(oneShot()) }
    func emit(_ s: LocationSample) { onSample?(s) }
    func setAuth(_ a: OSLocationAuth) { authorization = a; onAuthChange?(a) }   // user changed it in iOS Settings
}
#endif
