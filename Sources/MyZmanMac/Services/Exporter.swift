import AppKit
import UniformTypeIdentifiers

/// Exports the user's zmanim for a date range to CSV (opens in Excel/Numbers), like MyZman's export tool.
@MainActor
enum Exporter {
    static func exportCSV(from start: Date, to end: Date, settings: AppSettings) {
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        let fmt = ZmanFormat(settings)
        var rows: [[String]] = [["תאריך", "תאריך עברי", "יום"] + settings.zmanim.map(\.name)]

        var day = cal.startOfDay(for: min(start, end))
        let last = cal.startOfDay(for: max(start, end))
        while day <= last, rows.count < 3700 {
            let info = ZmanEngine.dayInfo(for: day, settings: settings)
            let zmanim = ZmanEngine.zmanim(on: day, settings: settings).map {
                $0.item.def?.isDuration == true ? ZmanFormat.duration($0.duration) : fmt.time($0.time)
            }
            rows.append([fmt.gregorianDate(day), info.hebrewDate, info.weekday] + zmanim)
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let csv = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "זמנים - \(settings.location.displayName).csv"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // UTF-8 BOM so Excel shows the Hebrew correctly.
        do { try Data(("\u{FEFF}" + csv).utf8).write(to: url) } catch {
            UserMessage.show("הייצוא נכשל: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func escape(_ s: String) -> String {
        s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }
}
