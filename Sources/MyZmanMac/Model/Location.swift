import Foundation
import KosherSwift

enum Region: String, Codable, CaseIterable, Identifiable {
    case israel, europe, usa, canada, australasia, other, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .israel: "ישראל"
        case .europe: "אירופה"
        case .usa: "ארה״ב"
        case .canada: "קנדה"
        case .australasia: "אוסטרליה"
        case .other: "שאר העולם"
        case .custom: "מיקומים שלי"
        }
    }
}

struct Location: Codable, Hashable, Identifiable {
    var nameHe: String
    var nameEn: String
    var region: Region
    var latitude: Double
    var longitude: Double
    var elevation: Double
    var timeZoneID: String

    var id: String { "\(nameEn)|\(latitude)|\(longitude)" }

    var displayName: String { nameHe.isEmpty ? nameEn : nameHe }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// Locations in Israel follow the Israeli holiday/parsha schedule by default.
    var isInIsrael: Bool { region == .israel || timeZoneID == "Asia/Jerusalem" }

    func geoLocation() -> GeoLocation {
        GeoLocation(locationName: nameEn, latitude: latitude, longitude: longitude,
                    elevation: max(0, elevation), timeZone: timeZone)
    }

    static let jerusalem = builtIn.first { $0.nameEn == "Jerusalem" }!
}
