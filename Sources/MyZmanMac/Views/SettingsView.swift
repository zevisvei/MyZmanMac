import SwiftUI

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
                Toggle("צבע לזמנים (אדום – עבר, כחול – עתידי)", isOn: $model.settings.colorPastZmanim)
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
            Section("ייצוא ל-Excel (CSV)") {
                DatePicker("מתאריך", selection: $exportFrom, displayedComponents: .date)
                    .environment(\.timeZone, model.tz)
                DatePicker("עד תאריך", selection: $exportTo, displayedComponents: .date)
                    .environment(\.timeZone, model.tz)
                Button("ייצא…") { Exporter.exportCSV(from: exportFrom, to: exportTo, settings: model.settings) }
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
                HStack {
                    if model.settings.menuBar.showIcon { Image(systemName: "sun.horizon") }
                    Text(model.menuBarTitle.isEmpty ? " " : model.menuBarTitle)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
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
                    HStack {
                        Text(loc.displayName)
                        Spacer()
                        Text(loc.region.title).font(.caption).foregroundStyle(.secondary)
                        if loc == model.settings.location { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(location: loc); draft = loc }
                    .contextMenu {
                        if loc.region == .custom {
                            Button("מחק") { model.settings.customLocations.removeAll { $0 == loc } }
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
                Section("מיקום מותאם / עריכה") {
                    TextField("שם", text: $draft.nameHe)
                    TextField("קו רוחב", value: $draft.latitude, format: .number.precision(.fractionLength(0...5)))
                    TextField("קו אורך", value: $draft.longitude, format: .number.precision(.fractionLength(0...5)))
                    TextField("גובה (מטרים)", value: $draft.elevation, format: .number)
                    Picker("אזור זמן", selection: $draft.timeZoneID) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        Button("שמור ובחר") {
                            var loc = draft
                            loc.region = .custom
                            if loc.nameHe.isEmpty { loc.nameHe = "מיקום שלי" }
                            loc.nameEn = loc.nameEn.isEmpty ? loc.nameHe : loc.nameEn
                            model.settings.customLocations.removeAll { $0.displayName == loc.displayName }
                            model.settings.customLocations.append(loc)
                            model.select(location: loc)
                        }
                        Button(locating ? "מאתר…" : "המיקום הנוכחי שלי") { locate() }.disabled(locating)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    Text("רשימת המיקומים נלקחה מ-MyZman ולא נבדקה; לרוב המיקומים חסר גובה.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { draft = model.settings.location }
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
                    ForEach($model.settings.zmanim) { $item in
                        HStack {
                            TextField("", text: $item.name).textFieldStyle(.plain)
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
                Text("גררו לשינוי הסדר, לחצו על שם לעריכה.").font(.caption).foregroundStyle(.secondary)
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
                        Button { delete(r.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
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
                } else {
                    DatePicker("שעה", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, model.tz)
                }

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
                case .daily:
                    EmptyView()
                }

                TextField("כותרת (לא חובה)", text: $draft.label)

                HStack {
                    if editingID != nil { Button("ביטול") { reset() } }
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
        default: true
        }
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
                    Button("ייצוא לקובץ ‎.ics…") { sync.exportICS(model.settings, options: model.settings.calendarSync) }
                    Spacer()
                    Button("הסר את מה שסונכרן", role: .destructive) {
                        run { try await sync.removeSynced(options: model.settings.calendarSync); return 0 }
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
            case .certificateAvailable?:
                Text("נמצאה תעודת מפתח במחשב. לחיצה אחת תחתום את האפליקציה ותפעיל את הווידג'טים. האפליקציה תיסגר ותיפתח מחדש.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(working ? "חותם…" : "הפעלת ווידג'טים") { enable() }.disabled(working)
            case .noCertificate?:
                Text("macOS מציג ווידג'טים רק של אפליקציות שחתומות בתעודת מפתח. אפשר לקבל תעודה בחינם, פעם אחת:")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. מתקינים את Xcode מה-App Store ופותחים אותו פעם אחת.")
                    Text("2. ‏Settings ← Accounts ← „+” ← מתחברים עם ה-Apple ID.")
                    Text("3. בוחרים בחשבון ← Manage Certificates ← „+” ← Apple Development.")
                    Text("4. חוזרים לכאן ולוחצים „בדוק שוב”.")
                }
                .font(.caption)
                HStack {
                    Button("פתח את Xcode ב-App Store") { NSWorkspace.shared.open(WidgetSigner.xcodeURL) }
                    Button("בדוק שוב") { refresh() }
                }
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
        do { try WidgetSigner.enable() } catch {
            self.error = error.localizedDescription
            working = false
        }
    }
}
