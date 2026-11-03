import AppKit
import UniformTypeIdentifiers

/// Exports the user's zmanim for a date range to CSV (opens in Excel/Numbers), like MyZman's export tool, or to a printable PDF.
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

    /// A printable luach: one row per day, the user's zmanim as columns, Shabbos and Yom Tov shaded,
    /// A4 landscape, as many pages as the range needs.
    static func exportPDF(from start: Date, to end: Date, settings: AppSettings) {
        let days = pdfDays(from: start, to: end, settings: settings)
        guard !days.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "לוח זמנים - \(settings.location.displayName).pdf"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if writePDF(days, settings: settings, to: url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            UserMessage.show("הייצוא נכשל")
        }
    }

    typealias PDFDay = (info: DayInfo, cells: [String], date: String, notes: String)

    static func pdfDays(from start: Date, to end: Date, settings: AppSettings) -> [PDFDay] {
        let cal = ZmanEngine.gregorian(settings.location.timeZone)
        let fmt = ZmanFormat(settings)
        var days: [PDFDay] = []
        var day = cal.startOfDay(for: min(start, end))
        let last = cal.startOfDay(for: max(start, end))
        while day <= last, days.count < 3700 {
            let info = ZmanEngine.dayInfo(for: day, settings: settings)
            let cells = ZmanEngine.zmanim(on: day, settings: settings).map {
                $0.item.def?.isDuration == true ? ZmanFormat.duration($0.duration, seconds: settings.showSeconds) : fmt.time($0.time)
            }
            let parsha = cal.component(.weekday, from: day) == 7 ? info.parsha : ""
            let special = SpecialTimes.on(day, settings: settings).map { "\($0.title) \(fmt.time($0.time))" }
            let notes = ([parsha] + info.events + special).filter { !$0.isEmpty }.joined(separator: " · ")
            days.append((info, cells, fmt.gregorianDate(day, style: "d/M"), notes))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    @discardableResult
    static func writePDF(_ days: [PDFDay], settings: AppSettings, to url: URL) -> Bool {
        guard let first = days.first, let lastDay = days.last else { return false }
        var page = CGRect(x: 0, y: 0, width: 842, height: 595)
        guard let pdf = CGContext(url as CFURL, mediaBox: &page, [
            kCGPDFContextTitle as String: url.deletingPathExtension().lastPathComponent,
            kCGPDFContextCreator as String: "MyZman",
        ] as CFDictionary) else { return false }
        let gc = NSGraphicsContext(cgContext: pdf, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = gc

        // Columns from the right: date, Hebrew date, the zmanim, then notes (parsha, holidays) on the left.
        let margin: CGFloat = 24
        let names = settings.zmanim.map(\.name)
        // A long list squeezes the notes column first, then the zmanim columns and the font, so it always fits the page.
        let dateW: CGFloat = 34, hebW: CGFloat = 62, count = CGFloat(max(names.count, 1))
        let avail = page.width - 2 * margin - dateW - hebW
        let notesW = min(150, max(80, avail - 26 * count))
        let zmanW = (avail - notesW) / count
        let size: CGFloat = zmanW >= 36 ? 8 : max(4, min(6.5, zmanW / 3.8))
        let inset: CGFloat = zmanW < 26 ? 0.5 : 2
        let widths = [dateW, hebW] + Array(repeating: zmanW, count: names.count) + [notesW]
        let titleH: CGFloat = 30, headerH: CGFloat = 30, footerH: CGFloat = 26, rowH: CGFloat = size + 6
        let perPage = Int((page.height - 2 * margin - titleH - headerH - footerH) / rowH)
        let title = "זמני היום – \(settings.location.displayName) – \(first.info.hebrewDate) עד \(lastDay.info.hebrewDate)"

        func draw(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool = false, align: NSTextAlignment = .center,
                  color: NSColor = .black) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.baseWritingDirection = .rightToLeft
            style.lineBreakMode = bold ? .byWordWrapping : .byTruncatingTail
            let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
            NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: color])
                .draw(with: rect.insetBy(dx: inset, dy: 0), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        func row(_ cells: [String], y: CGFloat, height: CGFloat, size: CGFloat, bold: Bool = false) {
            var x = page.width - margin
            for (i, (cell, w)) in zip(cells, widths).enumerated() {
                x -= w
                let align: NSTextAlignment = i == widths.count - 1 && !bold ? .right : .center
                draw(cell, in: CGRect(x: x, y: y + 2, width: w, height: height - 2), size: size, bold: bold, align: align)
            }
        }

        let pages = stride(from: 0, to: days.count, by: perPage).map { Array(days[$0..<min($0 + perPage, days.count)]) }
        for (n, chunk) in pages.enumerated() {
            pdf.beginPDFPage(nil)
            pdf.saveGState()
            pdf.translateBy(x: 0, y: page.height)   // top-down, like the flipped graphics context expects
            pdf.scaleBy(x: 1, y: -1)
            draw(title, in: CGRect(x: margin, y: margin, width: page.width - 2 * margin, height: titleH), size: 13, bold: true)
            var y = margin + titleH
            NSColor(white: 0.88, alpha: 1).setFill()
            CGRect(x: margin, y: y, width: page.width - 2 * margin, height: headerH).fill()
            row(["תאריך", "תאריך עברי"] + names + ["פרשה ומועדים"], y: y + 2, height: headerH, size: size, bold: true)
            y += headerH
            for d in chunk {
                if d.info.isShabbosOrYomTov {
                    NSColor(white: 0.94, alpha: 1).setFill()
                    CGRect(x: margin, y: y, width: page.width - 2 * margin, height: rowH).fill()
                }
                row([d.date, d.info.hebrewDayMonth] + d.cells + [d.notes], y: y, height: rowH, size: size)
                y += rowH
            }
            NSColor(white: 0.75, alpha: 1).setStroke()
            let grid = NSBezierPath()
            grid.lineWidth = 0.4
            var x = page.width - margin
            for w in widths.dropLast() { x -= w; grid.move(to: CGPoint(x: x, y: margin + titleH)); grid.line(to: CGPoint(x: x, y: y)) }
            grid.appendRect(CGRect(x: margin, y: margin + titleH, width: page.width - 2 * margin, height: y - margin - titleH))
            grid.stroke()
            draw("\(Disclaimer.short)   ·   עמוד \(n + 1) מתוך \(pages.count)",
                 in: CGRect(x: margin, y: page.height - margin - footerH + 8, width: page.width - 2 * margin, height: footerH),
                 size: 7, color: .darkGray)
            pdf.restoreGState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return true
    }

    private static func escape(_ s: String) -> String {
        s.contains(where: { ",\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
    }
}
