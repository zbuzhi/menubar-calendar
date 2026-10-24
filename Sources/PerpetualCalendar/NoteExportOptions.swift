import SwiftUI
import CalendarCore

struct NoteExportOptions: View {
    let document: NoteDocument
    let onExport: (NoteDocument,NoteExport.Format,String) -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var inheritedScheme
    @LocalState private var format: NoteExport.Format
    @LocalState private var start: Date
    @LocalState private var end: Date
    @LocalState private var allDates: Bool
    @LocalState private var selectedTags: Set<UUID>
    @LocalState private var untagged: Bool
    init(document: NoteDocument,date: Date,allDates: Bool,tagID: UUID?,format: NoteExport.Format,initialRange: NoteDateRange? = nil,
         onExport: @escaping (NoteDocument,NoteExport.Format,String) -> Void) {
        self.document = document; self.onExport = onExport
        let engine = CalendarEngine()
        func parse(_ key: String?) -> Date {
            let parts = key?.split(separator:"-").compactMap { Int($0) } ?? []
            return parts.count == 3 ? engine.date(parts[0],parts[1],parts[2]) : date
        }
        _format = LocalState(initialValue:format)
        _start = LocalState(initialValue:initialRange?.start != nil ? parse(initialRange?.start) : allDates ? parse(document.entries.map(\.date).min()) : date)
        _end = LocalState(initialValue:initialRange?.end != nil ? parse(initialRange?.end) : allDates ? parse(document.entries.map(\.date).max()) : date)
        _allDates = LocalState(initialValue:initialRange == nil && allDates)
        _selectedTags = LocalState(initialValue:tagID.map { Set([$0]) } ?? Set(document.tags.map(\.id)))
        _untagged = LocalState(initialValue:tagID == nil)
    }
    private var validRange: Bool { allDates || state.engine.key(start) <= state.engine.key(end) }
    private var entries: [NoteEntry] {
        guard validRange else { return [] }
        return document.exportEntries(from:allDates ? nil : state.engine.key(start),through:allDates ? nil : state.engine.key(end),tagIDs:selectedTags,includeUntagged:untagged)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("导出小记").font(.headline)
            Picker("格式",selection:$format) {
                Text("PDF").tag(NoteExport.Format.pdf)
                Text("Markdown").tag(NoteExport.Format.markdown)
                Text("JSON").tag(NoteExport.Format.json)
            }.pickerStyle(.segmented)
            Toggle("全部日期",isOn:$allDates)
            if !allDates {
                HStack {
                    DatePicker("从",selection:$start,displayedComponents:.date)
                    DatePicker("至",selection:$end,displayedComponents:.date)
                }.environment(\.timeZone,state.engine.calendar.timeZone)
            }
            HStack {
                Text("标签（可多选）").font(.system(size:12,weight:.medium))
                Spacer()
                Button("全选") { selectedTags = Set(document.tags.map(\.id)); untagged = true }
                Button("清空") { selectedTags = []; untagged = false }
            }
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
                    Toggle("未归类",isOn:$untagged)
                    ForEach(document.tags) { tag in
                        Toggle(isOn:Binding(get:{ selectedTags.contains(tag.id) },set:{ enabled in
                            if enabled { selectedTags.insert(tag.id) } else { selectedTags.remove(tag.id) }
                        })) {
                            HStack(spacing:5) { Circle().fill(NoteColors.color(tag.color)).frame(width:6,height:6); Text(tag.name).lineLimit(1) }
                        }
                    }
                }.padding(.vertical,4)
            }.frame(height:min(190,CGFloat((document.tags.count + 2) / 2) * 32))
            Text(validRange ? "共 \(entries.count) 条 · 包含起止日期，多标签记录只导出一次" : "起始日期不能晚于结束日期")
                .font(.caption).foregroundStyle(validRange ? Color.secondary : .red)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("选择保存位置…") {
                    var output = document; output.entries = entries
                    let title = allDates ? "全部日期的小记" : state.engine.key(start) + " 至 " + state.engine.key(end) + " 小记"
                    onExport(output,format,title)
                }.buttonStyle(.borderedProminent).disabled(entries.isEmpty || !validRange)
            }
        }.padding(24).frame(width:410).controlSize(.small)
            .foregroundStyle(SettingsPalette(state.colorScheme ?? inheritedScheme).text)
            .background(SettingsPalette(state.colorScheme ?? inheritedScheme).backing)
            .preferredColorScheme(state.colorScheme)
    }
}
