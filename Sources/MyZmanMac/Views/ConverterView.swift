import SwiftUI

/// Gregorian ↔ Hebrew date converter.
struct ConverterView: View {
    @EnvironmentObject var model: AppModel
    let onShow: () -> Void

    @ViewState private var gregorian = Date()
    @ViewState private var hYear = 5787
    @ViewState private var hMonth = 1
    @ViewState private var hDay = 1

    private var hebrew: Calendar {
        var c = Calendar(identifier: .hebrew)
        c.timeZone = model.tz
        c.locale = Locale(identifier: "he_IL")
        return c
    }

    /// Months that exist in the chosen year (Adar I only in leap years), in Apple's numbering.
    private func months(in year: Int) -> [(Int, String)] {
        let cal = hebrew
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "he_IL")
        f.timeZone = model.tz
        f.dateFormat = "MMMM"
        return (1...13).compactMap { m in
            guard let d = cal.date(from: DateComponents(era: 0, year: year, month: m, day: 1)),
                  cal.component(.month, from: d) == m else { return nil }
            return (m, f.string(from: d))
        }
    }

    private var hebrewResult: Date? {
        hebrew.date(from: DateComponents(era: 0, year: hYear, month: hMonth, day: hDay))
            .flatMap { hebrew.component(.day, from: $0) == hDay ? $0 : nil }
    }

    var body: some View {
        Form {
            Section("לועזי ← עברי") {
                LabeledContent("תאריך לועזי") { DateJumpButton(date: $gregorian) }
                let info = model.dayInfo(gregorian)
                result(info.hebrewDate, sub: ([info.weekday, info.parsha] + info.events).filter { !$0.isEmpty }.joined(separator: " · ")) {
                    model.selectedDate = gregorian
                }
            }
            Section("עברי ← לועזי") {
                HStack {
                    Picker("יום", selection: $hDay) {
                        ForEach(1...30, id: \.self) { Text(ZmanEngine.formatter.formatHebrewNumber(number: $0)).tag($0) }
                    }
                    Picker("חודש", selection: $hMonth) {
                        ForEach(months(in: hYear), id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Stepper(value: $hYear, in: 3800...6000) {
                    Text("שנה: \(ZmanEngine.formatter.formatHebrewNumber(number: hYear)) (\(String(hYear)))")
                }
                if let d = hebrewResult {
                    let info = model.dayInfo(d)
                    result(model.format.localizedDate(d, template: "EEEEdMMMMyyyy"),
                           sub: ([info.parsha] + info.events).filter { !$0.isEmpty }.joined(separator: " · ")) {
                        model.selectedDate = d
                    }
                } else {
                    Text("תאריך לא קיים").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            gregorian = model.selectedDate
            let c = hebrew.dateComponents([.year, .month, .day], from: model.selectedDate)
            hYear = c.year!; hMonth = c.month!; hDay = c.day!
        }
        .onChange(of: hYear) {
            if !months(in: hYear).contains(where: { $0.0 == hMonth }) { hMonth = 7 }
        }
    }

    private func result(_ main: String, sub: String, show: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(main).font(.headline).textSelection(.enabled)
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("זמנים") { show(); onShow() }
        }
    }
}
