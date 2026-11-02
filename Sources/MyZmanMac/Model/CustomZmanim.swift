import Foundation
import KosherSwift

/// Zmanim MyZman adds on top of KosherJava (its AddedGets class), plus a few
/// KosherJava methods that KosherSwift keeps private.
extension ComplexZmanimCalendar {
    private func offset(_ date: Date?, minutes: Double) -> Date? {
        date.map { $0.addingTimeInterval(minutes * 60) }
    }

    func myzMisheyakir50() -> Date? { offset(getSunrise(), minutes: -50) }

    func myzCandleLighting(_ minutes: Double) -> Date? { offset(getSunset(), minutes: -minutes) }

    func myzSunriseBaalHatanya() -> Date? { getSunriseOffsetByDegrees(offsetZenith: 90 + 1.583) }

    func myzSunsetBaalHatanya() -> Date? { getSunsetOffsetByDegrees(offsetZenith: 90 + 1.583) }

    func myzTzaisDegrees(_ degrees: Double) -> Date? { getSunsetOffsetByDegrees(offsetZenith: 90 + degrees) }

    func myzSofZmanShmaFixedLocal() -> Date? { offset(getFixedLocalChatzos(), minutes: -180) }

    func myzSofZmanTfilaFixedLocal() -> Date? { offset(getFixedLocalChatzos(), minutes: -120) }

    func myzPlagHamincha8Point5Degrees() -> Date? {
        getPlagHamincha(startOfDay: getSunriseOffsetByDegrees(offsetZenith: 90 + 8.5),
                        endOfDay: getSunsetOffsetByDegrees(offsetZenith: 90 + 8.5))
    }

    func myzBeinHashmashos8Point5Degrees13Min() -> Date? {
        offset(getSunsetOffsetByDegrees(offsetZenith: 90 + 8.5), minutes: -13.5)
    }

    func myzBeinHashmashos8Point5Degrees5Point3() -> Date? {
        guard let tzais = getTzaisGeonim8Point5Degrees(), let sunset = getSunset() else { return nil }
        let span = tzais.timeIntervalSince(sunset)
        return tzais.addingTimeInterval(-span / 5.3333)
    }
}
