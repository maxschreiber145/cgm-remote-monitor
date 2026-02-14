import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject {

    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var altitude: Double = 0
    @Published var horizontalAccuracy: Double = -1
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isReceivingUpdates = false

    private let manager = CLLocationManager()

    var currentLocation: CLLocation? {
        guard horizontalAccuracy >= 0 else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }

    var formattedCoordinate: String {
        guard horizontalAccuracy >= 0 else { return "Acquiring..." }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    var formattedAltitude: String {
        guard horizontalAccuracy >= 0 else { return "—" }
        return String(format: "%.0f m", altitude)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1 // Update every meter
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        isReceivingUpdates = false
    }
}

extension LocationService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        altitude = loc.altitude
        horizontalAccuracy = loc.horizontalAccuracy
        isReceivingUpdates = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationService] Error: \(error.localizedDescription)")
    }
}
