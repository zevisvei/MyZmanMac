import Foundation
import CoreLocation

/// One-shot lookup of the Mac's current location, reverse geocoded for a name and time zone.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Failure: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self {
            case .denied: "אין הרשאת מיקום. ניתן לאפשר בהגדרות המערכת ← פרטיות ואבטחה ← שירותי מיקום."
            case .unavailable: "לא ניתן לקבל את המיקום כרגע."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var request = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async throws -> Location {
        let fix = try await withCheckedThrowingContinuation { (c: CheckedContinuation<CLLocation, Error>) in
            continuation = c
            request += 1
            let current = request
            // Don't hang forever if the permission prompt is dismissed or no fix arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.request == current else { return }
                self.finish(.failure(Failure.unavailable))
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: manager.requestLocation()
            }
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(fix, preferredLocale: Locale(identifier: "he_IL")).first
        let name = placemark?.locality ?? placemark?.name ?? "המיקום שלי"
        return Location(nameHe: name, nameEn: name, region: .custom,
                        latitude: (fix.coordinate.latitude * 10_000).rounded() / 10_000,
                        longitude: (fix.coordinate.longitude * 10_000).rounded() / 10_000,
                        elevation: max(0, fix.altitude.rounded()),
                        timeZoneID: placemark?.timeZone?.identifier ?? TimeZone.current.identifier)
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorized, .authorizedWhenInUse: manager.requestLocation()
            case .denied, .restricted: finish(.failure(Failure.denied))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let l = locations.last { finish(.success(l)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(Failure.unavailable)) }
    }
}
