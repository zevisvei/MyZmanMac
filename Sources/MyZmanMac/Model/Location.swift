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

    var id: String { "\(region.rawValue)|\(nameEn)|\(latitude)|\(longitude)" }

    init(nameHe: String, nameEn: String, region: Region, latitude: Double, longitude: Double, elevation: Double, timeZoneID: String) {
        self.nameHe = nameHe; self.nameEn = nameEn; self.region = region
        self.latitude = latitude; self.longitude = longitude; self.elevation = elevation; self.timeZoneID = timeZoneID
    }

    // Lenient, like the rest of the settings: a missing or unknown field must not drop a location (and with it
    // the whole list of custom locations). Only the coordinates are required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        nameHe = (try? c.decode(String.self, forKey: .nameHe)) ?? ""
        nameEn = (try? c.decode(String.self, forKey: .nameEn)) ?? ""
        region = (try? c.decode(Region.self, forKey: .region)) ?? .custom
        elevation = (try? c.decode(Double.self, forKey: .elevation)) ?? 0
        timeZoneID = (try? c.decode(String.self, forKey: .timeZoneID)) ?? TimeZone.current.identifier
    }

    var displayName: String { nameHe.isEmpty ? nameEn : nameHe }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// Within Jerusalem's municipal area, where Purim is on 15 Adar and candles are lit 40 minutes before
    /// sunset. A box around the city that leaves out the towns next to it that keep the 14th – Givat Ze'ev
    /// (31.86, 35.16), Mevaseret Zion (31.80, 35.15), Ma'ale Adumim (31.77, 35.30), Beitar Illit (31.69, 35.12).
    var isJerusalem: Bool {
        (31.72...31.84).contains(latitude) && (35.17...35.26).contains(longitude)
    }

    /// Locations in Israel follow the Israeli holiday/parsha schedule by default.
    var isInIsrael: Bool { region == .israel || timeZoneID == "Asia/Jerusalem" }

    func geoLocation() -> GeoLocation {
        GeoLocation(locationName: nameEn, latitude: latitude, longitude: longitude,
                    elevation: max(0, elevation), timeZone: timeZone)
    }

    static let jerusalem = builtIn.first { $0.nameEn == "Jerusalem" }!
}
