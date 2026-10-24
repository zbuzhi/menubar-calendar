import SwiftUI
import CalendarCore
import ServiceManagement

@MainActor final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { savePreferences() } }
    @Published var selected = Date()
    @Published var month = Date() { didSet { if holidayUpdatesEnabled { refreshHolidays() } } }
    @Published var annual = false
    @Published var settingsPresented = false
    @Published var settingsTab = "appearance"
    @Published var formatTarget = "menu"
    @Published var settingsOnLeft = true
    @Published var settingsDock: SettingsDock = .left
    @Published var calendarViewportHeight: CGFloat?
    @Published var settingsViewportHeight: CGFloat?
    @Published var noteEditorDate: Date? { didSet { onNotePresentationChange?() } }
    static let defaultNoteEditorSize = NSSize(width:470,height:570)
    @Published private(set) var noteEditorSize = AppState.defaultNoteEditorSize
    @Published var noteSimpleDisplay = false { didSet { defaults.set(noteSimpleDisplay,forKey:"notes.simpleDisplay") } }
    @Published var notePinned = false { didSet { defaults.set(notePinned,forKey:"notes.pinned"); onNotePinChange?() } }
    private(set) var noteWindowOrigin: NSPoint?
    @Published var settingsWidth: CGFloat = 620
    @Published var availableHeight: CGFloat = 900
    @Published var pinned = false
    @Published var comparison = false
    @Published var comparisonDate = Date()
    @Published private(set) var noteDocument: NoteDocument
    private(set) var notesReadOnly = false
    private var notesSourceKey = "notes.v3"
    @Published var toast: String?
    @Published var loginError: String?
    let engine = CalendarEngine()
    @Published var holidays = HolidayCalendar()
    @Published var holidayStatus = "内置 2026 年调休 · 首次展开时检查更新"
    @Published var holidayUpdating = false
    private var holidayUpdatesEnabled = false
    private let holidayRepository = HolidayRepository()
    let softwareUpdater = SoftwareUpdater()
    var onNotePinChange: (() -> Void)?
    var onNotePresentationChange: (() -> Void)?
    var onNoteResetSize: (() -> Void)?
    var onNoteClose: (() -> Void)?
    var onNoteAdd: (() -> Void)?
    var onNoteSave: (() -> Void)?
    weak var noteUndoManager: UndoManager?
    var onSettings: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onPreferencesChange: (() -> Void)?
    var onPin: (() -> Void)?
    private var clearToast: Task<Void,Never>?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = defaults.data(forKey:"preferences.v1").flatMap { try? JSONDecoder().decode(Preferences.self,from:$0) } ?? Preferences()
        loaded.iconSize = CalendarMetrics.iconSize(loaded.iconSize)
        preferences = loaded
        notePinned = defaults.bool(forKey:"notes.pinned")
        noteSimpleDisplay = defaults.bool(forKey:"notes.simpleDisplay")
        if let origin = defaults.array(forKey:"notes.windowOrigin") as? [Double], origin.count == 2, origin.allSatisfy({ $0.isFinite }) {
            noteWindowOrigin = NSPoint(x:origin[0],y:origin[1])
        }
        if let size = defaults.array(forKey:"notes.editorSize") as? [Double], size.count == 2,
           size.allSatisfy({ $0.isFinite }) {
            noteEditorSize = NSSize(width:min(1600,max(380,size[0])),height:min(1600,max(300,size[1])))
        }
        notesSourceKey = defaults.data(forKey:"notes.v3") != nil ? "notes.v3" : "notes.v2"
        if let data = defaults.data(forKey:notesSourceKey) {
            do {
                noteDocument = try NoteDocument.decode(data)
                if notesSourceKey != "notes.v3", let migrated = try? noteDocument.encoded() { defaults.set(migrated,forKey:"notes.v3") }
            }
            catch { noteDocument = NoteDocument(); notesReadOnly = true }
        } else {
            noteDocument = NoteDocument.migrate(defaults.dictionary(forKey:"notes.v1") as? [String:String] ?? [:])
            if let data = try? noteDocument.encoded() { defaults.set(data,forKey:"notes.v3") }
        }
    }
    func setNoteWindowOrigin(_ origin: NSPoint) {
        noteWindowOrigin = origin; defaults.set([origin.x,origin.y],forKey:"notes.windowOrigin")
    }
    func toggleNoteEditor(_ date: Date) {
        noteEditorDate = noteEditorDate.map { engine.key($0) == engine.key(date) } == true ? nil : date
    }
    func setNoteEditorSize(_ size: NSSize) {
        let clamped = NSSize(width:min(1600,max(380,size.width)),height:min(1600,max(300,size.height)))
        guard noteEditorSize != clamped else { return }
        noteEditorSize = clamped
        defaults.set([clamped.width,clamped.height],forKey:"notes.editorSize")
    }
    var usesBoldText: Bool { preferences.boldText ?? false }
    func textWeight(_ normal: Font.Weight = .regular) -> Font.Weight { usesBoldText ? .bold : normal }
    var effectiveIconSize: Double { CalendarMetrics.iconSize(preferences.iconSize) }
    var calendarPanelHeight: CGFloat {
        let screen = availableHeight
        let p = preferences
        if annual { return min(screen - 65, comparison ? 760 : 650) }
        let dates = engine.monthDays(month,mondayFirst:p.mondayFirst)
        var gridHeight = 24.0
        for row in 0..<(dates.count/7) {
            let week = dates[(row*7)..<(row*7+7)]
            let icons = p.zodiac != "hidden" || (p.termIcons && week.contains { SolarTerms.on($0,engine:engine) != nil })
            gridHeight += p.compact ? (icons ? 62 : p.lunar ? 47 : 36) : (icons ? 74 : 58)
        }
        var detailHeight = 73.0
        if p.showGanZhi { detailHeight += 23 }
        if p.showDayProgress { detailHeight += 43 }
        if p.showWeek { detailHeight += 23 }
        if p.showCapsule { detailHeight += 36 }
        if p.showHolidayCountdown { detailHeight += 23 }
        if p.showNotes { detailHeight += 44 }
        return min(screen - 65, 116 + gridHeight + detailHeight + (comparison ? 160 : 0))
    }
    var workspaceHeight: CGFloat {
        if settingsPresented && settingsDock == .below, let c = calendarViewportHeight, let s = settingsViewportHeight { return c + s + 1 }
        return min(availableHeight - 12, settingsPresented ? max(480, calendarPanelHeight) : calendarPanelHeight)
    }
    private var accentName: String {
        if preferences.seasonal {
            let i = SolarTerms.surrounding(selected,engine:engine).current.index
            switch i { case 2..<8: return "green"; case 8..<14: return "teal"; case 14..<20: return "orange"; default: return "blue" }
        }
        return preferences.accent
    }
    var accent: Color {
        let dark = preferences.theme == "dark" || (preferences.theme == "system" && NSApp.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua)
        return color(ThemeColors.ink(accentName,dark:dark))
    }
    var selectionColor: Color { color(ThemeColors.selection(accentName)) }
    private func color(_ rgb: CalendarCore.RGBColor) -> Color { Color(.sRGB,red:rgb.red,green:rgb.green,blue:rgb.blue,opacity:1) }
    var colorScheme: ColorScheme? { preferences.theme == "system" ? nil : preferences.theme == "dark" ? .dark : .light }
    func hasNotes(on date: String) -> Bool { noteDocument.entries.contains { $0.date == date && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } }
    var note: String {
        let entries = noteDocument.entries(date:engine.key(selected)).filter { !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        guard !entries.isEmpty else { return "" }
        return "\(entries.filter(\.isCompleted).count)/\(entries.count) 已完成 · " + entries.map(\.text).joined(separator:" · ")
    }
    @discardableResult func saveNotes(_ document: NoteDocument) -> Bool {
        guard !notesReadOnly else { message("小记数据版本较新或已损坏，已保留原始数据，请先导出备份"); return false }
        do {
            try document.validate()
            let data = try document.encoded(pretty:false)
            defaults.set(data,forKey:"notes.v3")
            noteDocument = document
            return true
        } catch { message("保存失败：\(error.localizedDescription)"); return false }
    }
    var noteStorageDescription: String {
        let bytes = defaults.data(forKey:notesReadOnly ? notesSourceKey : "notes.v3")?.count ?? 0
        return "全部 \(noteDocument.entries.count) 条 · " + ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file)
    }
    var selectedYear: Int { engine.calendar.component(.year,from:month) }
    func openSettings(tab: String, target: String? = nil) {
        settingsTab = tab
        if let target { formatTarget = target }
        onShowSettings?()
    }
    func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data,forKey:"preferences.v1") }
        onPreferencesChange?()
    }
    func select(_ date: Date) { guard (1901...2100).contains(engine.calendar.component(.year,from:date)) else { message("支持查询 1901—2100 年"); return }; selected = date; if !engine.calendar.isDate(date,equalTo:month,toGranularity:.month) { month = date } }
    func today() { let now = Date(); selected = now; month = now; annual = false }
    func shift(_ amount: Int) {
        let component: Calendar.Component = annual ? .year : .month
        let target = engine.calendar.date(byAdding:component,value:amount,to:month)!
        let y = engine.calendar.component(.year,from:target)
        if (1901...2100).contains(y) { month = target }
    }
    func render(_ template: String, at date: Date) -> String { DateFormats.render(template,date:date,engine:engine,iso:preferences.isoWeek) }
    func copy(_ template: String, date: Date = Date()) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(render(template,at:date),forType:.string)
        message("已复制")
    }
    func message(_ text: String) {
        clearToast?.cancel(); toast = text
        clearToast = Task { try? await Task.sleep(nanoseconds:1_700_000_000); if !Task.isCancelled { toast = nil } }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                loginError = "请在系统设置 → 通用 → 登录项中允许日历启动。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { loginError = "无法更新登录项：\(error.localizedDescription)" }
        objectWillChange.send()
    }
    func refreshHolidays(force: Bool = false) {
        holidayUpdatesEnabled = true
        let year = selectedYear
        Task {
            holidayUpdating = true
            let cached = await holidayRepository.cachedRecords()
            applyHolidayRecords(cached)
            let record = await holidayRepository.load(year:year,force:force)
            applyHolidayRecords(await holidayRepository.cachedRecords())
            if selectedYear == year { holidayStatus = record.summary }
            holidayUpdating = false
        }
    }
    private func applyHolidayRecords(_ records: [HolidayYearRecord]) {
        var calendar = HolidayCalendar()
        for record in records.sorted(by: { $0.year < $1.year }) {
            calendar.entries.merge(record.entries) { _, new in new }
            if record.complete { calendar.coveredYears.insert(record.year) }
        }
        if calendar.entries != holidays.entries || calendar.coveredYears != holidays.coveredYears { holidays = calendar }
    }
    func exportNotes() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = AppBrand.noteExportName + ".json"
        guard NoteSaveDialog.run(panel) == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if notesReadOnly {
                guard let original = defaults.data(forKey:notesSourceKey) else { throw CocoaError(.fileReadNoSuchFile) }
                data = original
            } else { data = try noteDocument.encoded() }
            try data.write(to:url,options:.atomic); message("小记已导出")
        }
        catch { message("导出失败：\(error.localizedDescription)") }
    }
}
