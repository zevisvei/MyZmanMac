import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ViewState private var tab: Int

    init(initialTab: Int = 0) { _tab = ViewState(wrappedValue: initialTab) }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("כללי", systemImage: "gearshape") }.tag(0)
            MenuBarSettings().tabItem { Label("שורת התפריטים", systemImage: "menubar.rectangle") }.tag(1)
            LocationSettings().tabItem { Label("מיקום", systemImage: "mappin.and.ellipse") }.tag(2)
            ZmanimSettings().tabItem { Label("זמנים", systemImage: "list.bullet") }.tag(3)
            ReminderSettings().tabItem { Label("תזכורות", systemImage: "bell") }.tag(4)
            CalendarSettings().tabItem { Label("לוח שנה", systemImage: "calendar") }.tag(5)
        }
        .frame(width: 620, height: 560)
        .activatingApp()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    private static let nightfall = ZmanCatalog.all.filter {
        ["GetTzais", "GetBainHasmashosRT", "ZmanGetBeinHashmases"].contains(where: $0.id.hasPrefix)
    }
    @ViewState private var launchAtLogin = LoginItem.isEnabled
    @ViewState private var loginError: String?
    @ViewState private var exportFrom = Date()
    @ViewState private var exportTo = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

    var body: some View {
        Form {
            Section("תצוגה") {
                Picker("מראה", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("שעון 24 שעות", isOn: $model.settings.use24h)
                Toggle("הצג שניות", isOn: $model.settings.showSeconds)
                if !model.settings.showSeconds {
                    Picker("עיגול לדקה", selection: $model.settings.rounding) {
                        ForEach(ZmanRounding.allCases) { Text($0.title).tag($0) }
                    }
                    Text("„לחומרא”: זמן שממנו מותר להתחיל (נץ, צאת הכוכבים, מנחה) מעוגל כלפי מעלה, וזמן אחרון (סוף זמן, שקיעה, הדלקת נרות) כלפי מטה. כך נוהגים רוב הלוחות.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("צבע לזמנים (אדום – עבר, כחול – עתידי)", isOn: $model.settings.colorPastZmanim)
                Toggle("סדר את הזמנים לפי השעה (במקום לפי סדר הרשימה)", isOn: $model.settings.sortByTime)
                Toggle("התאריך העברי מתחלף בשקיעה", isOn: $model.settings.hebrewDateChangesAtSunset)
            }
            Section("לוח וחגים") {
                Picker("חגים ופרשות", selection: Binding(
                    get: { model.settings.inIsraelOverride.map { $0 ? 1 : 2 } ?? 0 },
                    set: { model.settings.inIsraelOverride = $0 == 0 ? nil : $0 == 1 })) {
                    Text("לפי המיקום").tag(0)
                    Text("ארץ ישראל").tag(1)
                    Text("חוץ לארץ").tag(2)
                }
                Toggle("הצג חגים ישראליים מודרניים", isOn: $model.settings.useModernHolidays)
            }
            Section("שבת, חגים וצומות") {
                Picker("הדלקת נרות", selection: $model.settings.candleLightingMinutes) {
                    Text("לפי המנהג המקומי (\(AppSettings.localCandleLighting(model.settings.location)) דק׳)").tag(Int?.none)
                    ForEach([15, 18, 20, 22, 25, 30, 40], id: \.self) { Text("\($0) דקות לפני השקיעה").tag(Optional($0)) }
                }
                Picker("צאת השבת והחג", selection: $model.settings.havdalahDefID) {
                    ForEach(Self.nightfall) { Text($0.he).tag($0.id) }
                }
                Picker("תחילת צום", selection: $model.settings.fastStartDefID) {
                    ForEach(ZmanCatalog.all.filter { $0.id.hasPrefix("GetAlos") }) {
                        Text($0.he).tag($0.id)
                    }
                }
                Picker("סוף צום (וספירת העומר)", selection: $model.settings.fastEndDefID) {
                    ForEach(Self.nightfall) { Text($0.he).tag($0.id) }
                }
                Picker("סוף תשעה באב", selection: $model.settings.tishaBavEndDefID) {
                    ForEach(Self.nightfall) { Text($0.he).tag($0.id) }
                }
                Picker("נרות חנוכה בימי חול", selection: $model.settings.chanukahAtTzais) {
                    Text("בשקיעה").tag(false)
                    Text("בצאת הכוכבים").tag(true)
                }
                Picker("נוסח", selection: $model.settings.nusach) {
                    ForEach(Nusach.allCases) { Text($0.title).tag($0) }
                }
                Text("הזמנים האלה מוצגים מעל רשימת הזמנים בימים שבהם הם חלים, ובווידג'ט זמני שבת.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("לימוד ותפילה") {
                Toggle("הצג שינויים בתפילה (יעלה ויבוא, הלל, תחנון…)", isOn: $model.settings.showTefila)
                Toggle("הצג דף יומי ירושלמי", isOn: $model.settings.showYerushalmi)
                Toggle("הצג את ההפטרה (לפי הנוסח שנבחר)", isOn: $model.settings.showHaftara)
                ForEach(DailyLearning.Cycle.allCases, id: \.self) { c in
                    Toggle(DailyLearning.title(c), isOn: Binding(
                        get: { model.settings.learning.contains(c) },
                        set: { on in
                            model.settings.learning.removeAll { $0 == c }
                            if on { model.settings.learning = DailyLearning.Cycle.allCases.filter { $0 == c || model.settings.learning.contains($0) } }
                        }))
                }
                Text("לימוד היום וההפטרה מוצגים בלחיצה על שורת הדף היומי.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("חישוב") {
                Toggle("חשב לפי גובה המיקום", isOn: $model.settings.useElevation)
                Toggle("אלגוריתם USNO הישן (במקום NOAA)", isOn: $model.settings.useUSNO)
                Text("כברירת מחדל החישוב לפי גובה פני הים ואלגוריתם NOAA, כמו ב-MyZman.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            WidgetSection()
            Section("מערכת") {
                Toggle("הפעל עם הכניסה למחשב", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        do { try LoginItem.set(launchAtLogin); loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = LoginItem.isEnabled }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("ייצוא לוח זמנים") {
                DatePicker("מתאריך", selection: $exportFrom, displayedComponents: .date)
                    .environment(\.timeZone, model.tz)
                DatePicker("עד תאריך", selection: $exportTo, displayedComponents: .date)
                    .environment(\.timeZone, model.tz)
                HStack {
                    Button("ל-Excel (CSV)…") { Exporter.exportCSV(from: exportFrom, to: exportTo, settings: model.settings) }
                    Button("להדפסה (PDF)…") { Exporter.exportPDF(from: exportFrom, to: exportTo, settings: model.settings) }
                }
            }
            Section {
                Text(Disclaimer.full)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Menu bar

private struct MenuBarSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let mb = $model.settings.menuBar
        Form {
            Section("תצוגה מקדימה") {
                MenuBarPreview(title: model.menuBar, showIcon: model.settings.menuBar.showIcon)
            }
            Section {
                Toggle("הצג בשורת התפריטים", isOn: mb.showInMenuBar)
                if !model.settings.menuBar.showInMenuBar {
                    Text("האפליקציה ממשיכה לפעול ברקע בשביל הווידג'טים והתזכורות. כדי לפתוח את חלון הזמנים: לחיצה על ווידג'ט, או פתיחת „זמנים” שוב מתיקיית היישומים או מ-Spotlight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("מה להציג") {
                Toggle("אייקון", isOn: mb.showIcon)
                Toggle("תאריך עברי", isOn: mb.showHebrewDate)
                Toggle("תאריך לועזי", isOn: mb.showGregorianDate)
            }
            Section("זמן") {
                Picker("איזה זמן", selection: mb.zmanMode) {
                    ForEach(MenuBarZmanMode.allCases) { Text($0.title).tag($0) }
                }
                if model.settings.menuBar.zmanMode == .next {
                    DisclosureGroup("אילו זמנים יוצגו") {
                        ForEach(model.settings.zmanim.filter { $0.def?.isDuration == false }) { item in
                            Toggle(item.name, isOn: Binding(
                                get: { !model.settings.menuBar.hiddenZmanim.contains(item.id) },
                                set: { on in
                                    model.settings.menuBar.hiddenZmanim.removeAll { $0 == item.id }
                                    if !on { model.settings.menuBar.hiddenZmanim.append(item.id) }
                                }))
                        }
                    }
                }
                if model.settings.menuBar.zmanMode == .pinned {
                    Picker("זמן קבוע", selection: mb.pinnedZman) {
                        Text("בחר…").tag(UUID?.none)
                        ForEach(model.settings.zmanim.filter { $0.def?.isDuration == false }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if model.settings.menuBar.zmanMode != .none {
                    Toggle("שם הזמן", isOn: mb.showZmanName)
                    Toggle("שעת הזמן", isOn: mb.showZmanTime)
                    Toggle("ספירה לאחור", isOn: mb.showCountdown)
                    if model.settings.menuBar.showCountdown {
                        Picker("הצג ספירה לאחור", selection: mb.countdownWithinMinutes) {
                            Text("תמיד").tag(0)
                            ForEach([15, 30, 60, 120], id: \.self) { Text("כשנותרו פחות מ-\($0) דקות").tag($0) }
                        }
                    }
                }
            }
            Section {
                Text("טיפ: לחיצה ימנית על זמן ברשימה מאפשרת להציג אותו בשורת התפריטים או להוסיף תזכורת.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Observes only the menu bar text, so the rest of the settings window doesn't redraw every minute.
private struct MenuBarPreview: View {
    @ObservedObject var title: MenuBarTitle
    let showIcon: Bool

    var body: some View {
        HStack {
            if showIcon { Image(systemName: "sun.horizon") }
            Text(title.text.isEmpty ? " " : title.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
    }
}

// MARK: - Location

private struct LocationSettings: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var search = ""
    @ViewState private var draft = Location(nameHe: "", nameEn: "", region: .custom, latitude: 31.778, longitude: 35.235,
                                        elevation: 0, timeZoneID: TimeZone.current.identifier)
    @ViewState private var locating = false
    @ViewState private var error: String?
    @ViewState private var locator = LocationService()

    private var results: [Location] {
        let all = model.settings.customLocations.sorted { $0.displayName < $1.displayName }
            + Location.builtIn.sorted { $0.displayName < $1.displayName }
        guard !search.isEmpty else { return all }
        return all.filter { $0.nameHe.contains(search) || $0.nameEn.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField("חיפוש עיר", text: $search).textFieldStyle(.roundedBorder)
                List(results) { loc in
                    let favorite = model.settings.favoriteLocations.contains(loc)
                    HStack {
                        Button { toggleFavorite(loc) } label: {
                            Label(favorite ? "הסר מהמועדפים" : "הוסף למועדפים", systemImage: favorite ? "star.fill" : "star")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(favorite ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(favorite ? "הסר מהמועדפים" : "הוסף למועדפים – יופיע ראשון בתפריט המיקום")
                        Text(loc.displayName)
                        Spacer()
                        Text(loc.region.title).font(.caption).foregroundStyle(.secondary)
                        if loc == model.settings.location { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(location: loc); draft = loc }
                    .contextMenu {
                        Button(favorite ? "הסר מהמועדפים" : "הוסף למועדפים") { toggleFavorite(loc) }
                        if loc.region == .custom {
                            Button("מחק") {
                                model.settings.customLocations.removeAll { $0 == loc }
                                model.settings.favoriteLocations.removeAll { $0 == loc }
                            }
                        }
                    }
                }
            }
            .frame(width: 230)
            .padding()

            Form {
                Section("נבחר כעת") {
                    let l = model.settings.location
                    LabeledContent("מיקום", value: l.displayName)
                    LabeledContent("קואורדינטות", value: String(format: "%.4f, %.4f", l.latitude, l.longitude))
                    LabeledContent("גובה", value: "\(Int(l.elevation)) מ׳")
                    LabeledContent("אזור זמן", value: l.timeZoneID)
                }
                Section {
                    TextField("שם", text: $draft.nameHe)
                    TextField("קו רוחב", value: $draft.latitude, format: .number.precision(.fractionLength(0...5)))
                    TextField("קו אורך", value: $draft.longitude, format: .number.precision(.fractionLength(0...5)))
                    TextField("גובה (מטרים)", value: $draft.elevation, format: .number)
                    LabeledContent("אזור זמן") { TimeZoneMenu(selection: $draft.timeZoneID) }
                    if !coordinatesValid {
                        Text("קו רוחב בין ‎-90 ל-90, קו אורך בין ‎-180 ל-180.").font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("שמור ובחר") {
                            var loc = draft
                            loc.region = .custom
                            if loc.nameHe.isEmpty { loc.nameHe = "מיקום שלי" }
                            loc.nameEn = loc.nameEn.isEmpty ? loc.nameHe : loc.nameEn
                            model.settings.customLocations.removeAll { $0.displayName == loc.displayName }
                            model.settings.customLocations.append(loc)
                            // An edited favorite stays a favorite, with its new details.
                            if let i = model.settings.favoriteLocations.firstIndex(where: {
                                $0.region == .custom && $0.displayName == loc.displayName
                            }) {
                                model.settings.favoriteLocations[i] = loc
                            }
                            model.select(location: loc)
                        }
                        .disabled(!coordinatesValid)
                        Button(locating ? "מאתר…" : "המיקום הנוכחי שלי") { locate() }.disabled(locating)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    HStack {
                        Text("מיקום מותאם / עריכה")
                        Spacer()
                        Button { newLocation() } label: { Label("מיקום חדש", systemImage: "plus") }
                            .buttonStyle(.borderless)
                            .help("טופס ריק להוספת מיקום חדש")
                    }
                }
                VisibleSunriseSection()
                Section {
                    Text("רשימת המיקומים נלקחה מ-MyZman ולא נבדקה; לרוב המיקומים חסר גובה.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { draft = model.settings.location }
    }

    private func toggleFavorite(_ loc: Location) {
        if model.settings.favoriteLocations.contains(loc) {
            model.settings.favoriteLocations.removeAll { $0 == loc }
        } else {
            model.settings.favoriteLocations.append(loc)
        }
    }

    private func newLocation() {
        let here = model.settings.location
        draft = Location(nameHe: "", nameEn: "", region: .custom, latitude: here.latitude, longitude: here.longitude,
                         elevation: 0, timeZoneID: here.timeZoneID)
        error = nil
    }

    private var coordinatesValid: Bool {
        (-90...90).contains(draft.latitude) && (-180...180).contains(draft.longitude) && (-500...9000).contains(draft.elevation)
    }

    private func locate() {
        locating = true
        error = nil
        Task {
            do { draft = try await locator.currentLocation() } catch { self.error = error.localizedDescription }
            locating = false
        }
    }
}

/// Importing a ChaiTables visible sunrise/sunset table for the selected location.
private struct VisibleSunriseSection: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var importing = false
    @ViewState private var message: String?
    @ViewState private var failed = false
    /// The ChaiTables city whose table to open, preset from the selected location.
    @ViewState private var city = ""

    private var key: String {
        VisibleSunriseTable.key(latitude: model.settings.location.latitude, longitude: model.settings.location.longitude)
    }

    var body: some View {
        let table = model.settings.visibleSunrise[key]
        Section("נץ ושקיעה הנראים (חי טבלאות)") {
            if let table, let range = table.dateRange {
                LabeledContent("לוח ל\(model.settings.location.displayName)",
                               value: "\(range.first) – \(range.last)")
                    .help(table.source)
            }
            let sefard = model.settings.nusach == .sefard
            if model.settings.location.region == .israel {
                Picker("העיר בחי טבלאות", selection: $city) {
                    Text("בחרו עיר").tag("")
                    ForEach(ChaiTables.cities, id: \.self) { Text(ChaiTables.displayName($0)).tag($0) }
                }
                Button("פתיחת הלוח של העיר באתר") {
                    NSWorkspace.shared.open(ChaiTables.tableURL(city: city, hebrewYear: ChaiTables.currentHebrewYear(in: model.tz),
                                                                sefard: sefard))
                }
                .disabled(city.isEmpty)
                .help("פותח בדפדפן את לוח הנץ והשקיעה הנראים של השנה. שומרים את הדף (⌘S) ומייבאים אותו כאן.")
            } else {
                Button("פתיחת אתר חי טבלאות") { NSWorkspace.shared.open(ChaiTables.site) }
            }
            HStack {
                Button(table == nil ? "ייבוא מקובץ…" : "ייבוא שנה נוספת מקובץ…", action: pick)
                    .disabled(importing)
                if table != nil {
                    Button("מחיקת הלוח") {
                        model.settings.visibleSunrise[key] = nil
                        message = nil
                    }
                }
                Spacer()
                if table != nil, !shown("VisibleSunrise") || (!(table?.sunset.isEmpty ?? true) && !shown("VisibleSunset")) {
                    Button("הוסף לרשימת הזמנים", action: addZmanim)
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(failed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("""
            הלוח נשמר למיקום שנבחר כעת. בארץ: „פתיחת הלוח של העיר באתר” (אם המיקום לא ברשימה, בחרו את העיר הקרובה), \
            שומרים את הדף שנפתח (⌘S) ומייבאים אותו. בחו״ל: באתר בוחרים מדינה ועיר, ובסוג הלוח „זריחה ושקיעה הנראים”. \
            אפשר גם קובץ ‎.ics מהאתר החדש של חי טבלאות, או CSV עם תאריך לועזי בכל שורה.
            """)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { city = ChaiTables.city(for: model.settings.location) ?? "" }
        .onChange(of: model.settings.location) { city = ChaiTables.city(for: model.settings.location) ?? "" }
    }

    private func save(_ t: VisibleSunriseTable, for key: String, place: String) {
        let isNew = model.settings.visibleSunrise[key] == nil
        model.settings.visibleSunrise[key] = model.settings.visibleSunrise[key].map { $0.merging(t) } ?? t
        if isNew, key == self.key { addZmanim() }
        failed = false
        let range = t.dateRange.map { " (\($0.first) עד \($0.last))" } ?? ""
        message = "יובאו \(t.sunrise.count) ימי נץ ו-\(t.sunset.count) ימי שקיעה\(range)\(place.isEmpty ? "" : " – " + place)."
    }

    private func shown(_ defID: String) -> Bool { model.settings.zmanim.contains { $0.defID == defID } }

    private func addZmanim() {
        // Each right after its sea-level counterpart in the user's list, or at the end.
        for (id, after, name) in [("VisibleSunrise", "GetSunrise", "נץ הנראה"), ("VisibleSunset", "GetSunset", "שקיעה הנראית")]
        where !shown(id) && (id == "VisibleSunrise" || !(model.settings.visibleSunrise[key]?.sunset.isEmpty ?? true)) {
            let item = ZmanItem(name: name, defID: id)
            if let i = model.settings.zmanim.firstIndex(where: { $0.defID == after }) {
                model.settings.zmanim.insert(item, at: i + 1)
            } else {
                model.settings.zmanim.append(item)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html, .webArchive, .commaSeparatedText, .tabSeparatedText, .plainText,
                                     .calendarEvent, .data]
        panel.allowsMultipleSelection = true
        panel.message = "בחרו את הדף השמור מחי טבלאות (HTML), קובץ ‎.ics או CSV"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls, tz = model.settings.location.timeZoneID, key = key
        importing = true
        message = nil
        Task {
            // The parse is heavy regex work: off the main thread.
            let result = await Task.detached { () -> Result<VisibleSunriseTable, Error> in
                do {
                    var merged: VisibleSunriseTable?
                    for url in urls {
                        let t = try VisibleSunriseTable.parse(try Data(contentsOf: url), fileName: url.lastPathComponent, timeZoneID: tz)
                        merged = merged.map { $0.merging(t) } ?? t
                    }
                    return merged.map(Result.success) ?? .failure(CocoaError(.fileReadUnknown))
                } catch { return .failure(error) }
            }.value
            importing = false
            switch result {
            case .success(let t):
                save(t, for: key, place: t.locationName)
                message = (message ?? "") + " ודאו שהלוח הוא של \(model.settings.location.displayName)."
            case .failure(let error):
                failed = true
                message = error.localizedDescription
            }
        }
    }
}

/// Time zones grouped by area (Asia, Europe…), instead of one flat list of ~600.
private struct TimeZoneMenu: View {
    @Binding var selection: String

    private static let groups: [(String, [String])] = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers) {
        $0.split(separator: "/").first.map(String.init) ?? $0
    }
    .sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted()) }

    var body: some View {
        Menu(selection) {
            ForEach(Self.groups, id: \.0) { area, ids in
                if ids.count == 1 {
                    Button(ids[0]) { selection = ids[0] }
                } else {
                    Menu(area) {
                        ForEach(ids, id: \.self) { id in
                            Button(id.dropFirst(area.count + 1).replacingOccurrences(of: "_", with: " ")) { selection = id }
                        }
                    }
                }
            }
        }
        .fixedSize()
    }
}

// MARK: - Zmanim list

private struct ZmanimSettings: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var search = ""
    @ViewState private var selection: UUID?

    private var catalog: [ZmanDef] {
        guard !search.isEmpty else { return ZmanCatalog.all }
        return ZmanCatalog.all.filter { $0.he.contains(search) || $0.en.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("הרשימה שלי").font(.headline)
                List(selection: $selection) {
                    ForEach(model.settings.zmanim) { item in
                        HStack {
                            ZmanNameField(item: item)
                            Spacer()
                            Text(item.def?.he ?? "?").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .tag(item.id)
                    }
                    .onMove { model.settings.zmanim.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { model.settings.zmanim.remove(atOffsets: $0) }
                }
                .onDeleteCommand { remove() }
                HStack {
                    Button("הסר") { remove() }.disabled(selection == nil)
                    Spacer()
                    Button("שחזר ברירת מחדל") { model.restoreDefaultZmanim() }
                }
                Text(model.settings.sortByTime
                     ? "הזמנים מוצגים לפי השעה (הגדרות ← כללי). הסדר כאן קובע רק כשיש שני זמנים באותה שעה."
                     : "גררו לשינוי הסדר, לחצו על שם לעריכה.").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("כל הזמנים (\(ZmanCatalog.all.count))").font(.headline)
                TextField("חיפוש", text: $search).textFieldStyle(.roundedBorder)
                List(catalog) { def in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(def.he)
                            Text(def.en).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let inList = model.settings.zmanim.contains { $0.defID == def.id }
                        Button { model.settings.zmanim.append(ZmanItem(name: def.he, defID: def.id)) } label: {
                            Image(systemName: inList ? "checkmark.circle.fill" : "plus.circle.fill")
                                .foregroundStyle(inList ? Color.green : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .help(inList ? "כבר ברשימה – לחיצה תוסיף עותק נוסף" : "הוסף לרשימה")
                    }
                    .help(def.heInfo + "\n\n" + def.enInfo)
                }
            }
        }
        .padding()
    }

    private func remove() {
        guard let selection else { return }
        model.settings.zmanim.removeAll { $0.id == selection }
        model.settings.reminders.removeAll { $0.zmanID == selection }
        self.selection = nil
    }
}

/// Edits a zman's name in a draft and saves it on Return or when the field loses focus – not on every
/// keystroke (each settings change saves, reschedules reminders and reloads the widgets).
private struct ZmanNameField: View {
    @EnvironmentObject var model: AppModel
    let item: ZmanItem
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { draft = item.name }
            .onChange(of: item.name) { if !focused { draft = item.name } }
            .onChange(of: focused) { if !focused { commit() } }
            .onSubmit(commit)
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard let i = model.settings.zmanim.firstIndex(where: { $0.id == item.id }) else { return }
        if name.isEmpty { draft = item.name; return }
        if model.settings.zmanim[i].name != name { model.settings.zmanim[i].name = name }
    }
}

// MARK: - Reminders

private struct ReminderSettings: View {
    @EnvironmentObject var model: AppModel
    @ViewState private var draft = Reminder(kind: .zman)
    @ViewState private var editingID: UUID?
    @ViewState private var time = Date()

    private var timedZmanim: [ZmanItem] { model.settings.zmanim.filter { $0.def?.isDuration == false } }

    var body: some View {
        let s = model.settings
        Form {
            Section("התזכורות שלי") {
                if s.reminders.isEmpty {
                    Text("אין תזכורות").foregroundStyle(.secondary)
                }
                ForEach($model.settings.reminders) { $r in
                    HStack {
                        Toggle("", isOn: $r.enabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title(in: s))
                            Text(r.summary(in: s, format: model.format)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("ערוך") { edit(r) }.buttonStyle(.link)
                        Button { delete(r.id) } label: { Label("מחק תזכורת", systemImage: "trash").labelStyle(.iconOnly) }.buttonStyle(.borderless)
                    }
                    .opacity(r.enabled ? 1 : 0.5)
                }
            }

            Section(editingID == nil ? "תזכורת חדשה" : "עריכת תזכורת") {
                Picker("סוג", selection: $draft.kind) {
                    ForEach(Reminder.Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if draft.kind == .zman {
                    Picker("זמן", selection: $draft.zmanID) {
                        Text("בחר…").tag(UUID?.none)
                        ForEach(timedZmanim) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Stepper(draft.minutesBefore == 0 ? "בזמן עצמו" : "\(draft.minutesBefore) דקות לפני",
                            value: $draft.minutesBefore, in: 0...240, step: 5)
                } else if draft.kind.hasOwnDays {
                    let (at, when): (String, String) = switch draft.kind {
                    case .candles: ("ההדלקה", "בכל ערב שבת וערב חג, לפי זמן הדלקת הנרות שבהגדרות ← כללי.")
                    case .havdalah: ("צאת השבת", "במוצאי שבת ובמוצאי חג, לפי צאת השבת שבהגדרות ← כללי.")
                    default: ("צאת הכוכבים", "בכל לילה מליל ב׳ של פסח עד ערב שבועות, עם הספירה של הלילה. צאת הכוכבים לפי ההגדרות ← כללי.")
                    }
                    Stepper(draft.minutesBefore == 0 ? "ב\(at)" : "\(draft.minutesBefore) דקות לפני \(at)",
                            value: $draft.minutesBefore, in: 0...240, step: 5)
                    Text(when).font(.caption).foregroundStyle(.secondary)
                } else {
                    DatePicker("שעה", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, model.tz)
                }

                if !draft.kind.hasOwnDays {
                Picker("חזרה", selection: $draft.repeatMode) {
                    ForEach(Reminder.Repeat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch draft.repeatMode {
                case .weekdays:
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = draft.weekdays.contains(d)
                            Button(Reminder.weekdayLetters[d - 1]) {
                                if on { draft.weekdays.removeAll { $0 == d } } else { draft.weekdays.append(d) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? .accentColor : .secondary)
                            .fontWeight(on ? .bold : .regular)
                        }
                    }
                    HStack {
                        Button("א׳–ה׳") { draft.weekdays = [1, 2, 3, 4, 5] }
                        Button("א׳–ו׳") { draft.weekdays = [1, 2, 3, 4, 5, 6] }
                        Button("שבת") { draft.weekdays = [7] }
                    }
                    .buttonStyle(.link).font(.caption)
                case .once:
                    LabeledContent("תאריך") {
                        DateJumpButton(date: Binding(get: { draft.onceDate ?? Date() }, set: { draft.onceDate = $0 }))
                    }
                case .daily, .erevShabbos:
                    EmptyView()
                }
                }

                TextField("כותרת (לא חובה)", text: $draft.label)

                HStack {
                    if editingID != nil { Button("ביטול") { reset() } }
                    if isPastOnce {
                        Text("המועד הזה כבר עבר – התזכורת לא תופיע.").font(.caption).foregroundStyle(.red)
                    }
                    Spacer()
                    Button(editingID == nil ? "הוסף תזכורת" : "שמור שינויים", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid)
                }
            }

            Section("ההתראות הקרובות") {
                let next = ReminderScheduler.plan(s, days: 14).prefix(8)
                if next.isEmpty {
                    Text("אין התראות בשבועיים הקרובים").foregroundStyle(.secondary)
                }
                ForEach(Array(next.enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(p.title)
                        Spacer()
                        Text(model.format.localizedDate(p.fire, template: "EEEdMMM") + " " + model.format.time(p.fire))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Text("התזכורות מוצגות כהתראות מערכת לפי המיקום הנבחר. הן נקבעות לשבועיים קדימה ומתחדשות כל יום כשהאפליקציה רצה (מומלץ להשאיר את ההפעלה עם הכניסה למחשב).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { reset() }
    }

    private var isValid: Bool {
        switch (draft.kind, draft.repeatMode) {
        case (.zman, _) where draft.zmanID == nil: false
        case (_, .weekdays) where draft.weekdays.isEmpty: false
        case (_, .once) where isPastOnce: false
        default: true
        }
    }

    /// A one-time reminder whose moment has already passed would never fire.
    private var isPastOnce: Bool {
        guard draft.repeatMode == .once else { return false }
        var r = draft
        let c = ZmanEngine.gregorian(model.tz).dateComponents([.hour, .minute], from: time)
        r.hour = c.hour ?? 8
        r.minute = c.minute ?? 0
        let day = ZmanEngine.noon(of: r.onceDate ?? Date(), in: model.tz)
        guard let fire = r.fireDate(on: day, settings: model.settings) else { return r.kind == .zman && r.zmanID != nil }
        return fire <= Date()
    }

    private func edit(_ r: Reminder) {
        draft = r
        editingID = r.id
        time = ZmanEngine.gregorian(model.tz).date(bySettingHour: r.hour, minute: r.minute, second: 0, of: Date()) ?? Date()
    }

    private func reset() {
        draft = Reminder(kind: .zman)
        draft.onceDate = Date()
        editingID = nil
        time = ZmanEngine.gregorian(model.tz).date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private func save() {
        var r = draft
        let c = ZmanEngine.gregorian(model.tz).dateComponents([.hour, .minute], from: time)
        r.hour = c.hour ?? 8
        r.minute = c.minute ?? 0
        if r.repeatMode == .once, r.onceDate == nil { r.onceDate = Date() }
        if r.kind.hasOwnDays { r.repeatMode = .daily }
        if let id = editingID, let i = model.settings.reminders.firstIndex(where: { $0.id == id }) {
            model.settings.reminders[i] = r
        } else {
            model.settings.reminders.append(r)
        }
        reset()
    }

    private func delete(_ id: UUID) {
        model.settings.reminders.removeAll { $0.id == id }
        if editingID == id { reset() }
    }
}

// MARK: - Calendar integration

private struct CalendarSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var sync = CalendarSync.shared
    @ViewState private var status: String?
    @ViewState private var busy = false

    var body: some View {
        let o = $model.settings.calendarSync
        let _ = sync.version
        Form {
            if !sync.hasAccess {
                Section {
                    HStack {
                        Text("כדי לקרוא ולכתוב ליומן (כולל יומן Google שמחובר למק) יש לאשר גישה.")
                        Spacer()
                        Button("אשר גישה") { run { try await sync.requestAccess(); return 0 } }
                    }
                }
            }

            Section("כתיבה ליומן") {
                Picker("לוח יעד", selection: o.targetCalendarID) {
                    Text("לוח חדש „\(CalendarSync.calendarTitle)” (iCloud / במחשב)").tag(String?.none)
                    ForEach(grouped(sync.writableCalendars()), id: \.0) { account, cals in
                        Section(account) {
                            ForEach(cals) { c in
                                Label { Text(c.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: c.color)) }
                                    .tag(Optional(c.id))
                            }
                        }
                    }
                }
                Text("ליומן Google: הוסיפו את חשבון Google בהגדרות המערכת ← חשבונות אינטרנט (עם לוחות שנה), צרו ב-Google לוח בשם „זמנים” ובחרו אותו כאן. המק לא יכול ליצור לוח חדש בחשבון Google. האפליקציה מוחקת ומעדכנת רק אירועים שהיא עצמה יצרה.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("סנכרן אוטומטית (מתעדכן כל יום)", isOn: o.enabled)
                Stepper("ימים קדימה: \(model.settings.calendarSync.daysAhead)", value: o.daysAhead, in: 7...365, step: 7)
                Toggle("תאריך עברי (אירוע של יום שלם)", isOn: o.includeHebrewDate)
                Toggle("חגים, ראש חודש, ספירת העומר ופרשת השבוע", isOn: o.includeEvents)
                Toggle("זמנים מיוחדים: הדלקת נרות, צאת שבת וחג, צומות, חמץ", isOn: o.includeSpecialTimes)
                Picker("התראה לזמנים", selection: o.alertMinutes) {
                    Text("ללא").tag(Int?.none)
                    ForEach([0, 5, 10, 15, 30], id: \.self) { Text($0 == 0 ? "בזמן" : "\($0) דק׳ לפני").tag(Optional($0)) }
                }
            }
            Section("זמנים שייכתבו ליומן") {
                ForEach(model.settings.zmanim.filter { $0.def?.isDuration == false }) { item in
                    Toggle(item.name, isOn: Binding(
                        get: { model.settings.calendarSync.zmanIDs.contains(item.id) },
                        set: { on in
                            model.settings.calendarSync.zmanIDs.removeAll { $0 == item.id }
                            if on { model.settings.calendarSync.zmanIDs.append(item.id) }
                        }))
                }
            }
            Section {
                HStack {
                    Button("סנכרן עכשיו") { run { try await sync.sync(model.settings, options: model.settings.calendarSync) } }
                    Button("ייצוא לקובץ ‎.ics…") {
                        do { try sync.exportICS(model.settings, options: model.settings.calendarSync) }
                        catch { status = "הייצוא נכשל: \(error.localizedDescription)" }
                    }
                    Spacer()
                    Button("הסר את מה שסונכרן", role: .destructive) {
                        // Turn the auto-sync off too, or it would write everything again at the next day rollover.
                        let options = model.settings.calendarSync
                        model.settings.calendarSync.enabled = false
                        run { try await sync.removeSynced(options: options); return 0 }
                    }
                }
                .disabled(busy)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }

            Section("קריאה מהיומן") {
                Toggle("הצג את האירועים שלי ליד הזמנים", isOn: o.showCalendarEvents)
                if model.settings.calendarSync.showCalendarEvents && sync.hasAccess {
                    Text("לוחות להצגה (אם לא נבחר אף אחד – כולם)").font(.caption).foregroundStyle(.secondary)
                    ForEach(grouped(sync.allCalendars()), id: \.0) { account, cals in
                        Text(account).font(.caption.bold())
                        ForEach(cals) { c in
                            Toggle(isOn: Binding(
                                get: { model.settings.calendarSync.readCalendarIDs.contains(c.id) },
                                set: { on in
                                    model.settings.calendarSync.readCalendarIDs.removeAll { $0 == c.id }
                                    if on { model.settings.calendarSync.readCalendarIDs.append(c.id) }
                                })) {
                                Label { Text(c.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: c.color)) }
                            }
                        }
                    }
                }
            }
            Section {
                Text("טיפ: ביומן של macOS אפשר גם להציג את הלוח העברי כלוח משני (הגדרות ← כללי ← לוחות שנה חלופיים).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func grouped(_ cals: [CalendarSync.CalendarInfo]) -> [(String, [CalendarSync.CalendarInfo])] {
        Dictionary(grouping: cals, by: \.account).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func run(_ op: @escaping () async throws -> Int) {
        busy = true
        status = nil
        Task {
            do {
                let n = try await op()
                status = n > 0 ? "נכתבו \(n) אירועים ליומן." : "בוצע."
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - Widgets

private struct WidgetSection: View {
    @ViewState private var status: WidgetSigner.Status?
    @ViewState private var error: String?
    @ViewState private var working = false

    var body: some View {
        Section("ווידג'טים") {
            switch status {
            case .none:
                ProgressView().controlSize(.small)
            case .enabled(let authority)?:
                Label("הווידג'טים פעילים", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Text("האפליקציה חתומה בתעודה: \(authority). להוספה: לחיצה ימנית על שולחן העבודה ← „עריכת ווידג'טים” ← חפשו „זמנים”.")
                    .font(.caption).foregroundStyle(.secondary)
            case .adHoc?:
                Text("העותק הזה חתום בחתימה מקומית בלבד, ולכן macOS לא מציג את הווידג'טים שלו. לחיצה אחת תיצור תעודת חתימה מקומית (בלי Xcode ובלי Apple ID), תחתום את האפליקציה ותפתח אותה מחדש.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(working ? "חותם…" : "הפעלת ווידג'טים") { enable() }.disabled(working)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        status = nil
        DispatchQueue.global().async {
            let s = WidgetSigner.status()
            DispatchQueue.main.async { status = s }
        }
    }

    private func enable() {
        working = true
        error = nil
        Task {
            do { try await WidgetSigner.enable() } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}
