import AppKit
import SwiftUI
import CalendarCore

@MainActor final class NoteDraft: ObservableObject {
    @Published var document = NoteDocument()
    @Published var saveStatus = "已自动保存"
    let undo = UndoManager()
    private weak var state: AppState?
    private var lastSaved: NoteDocument?
    private var pending: Task<Void,Never>?
    func begin(_ state: AppState) { self.state = state; document = state.noteDocument; lastSaved = document }
    func change(_ update: (inout NoteDocument) -> Void) {
        var next = document; update(&next)
        guard next != document else { return }
        replace(next)
    }
    private func replace(_ next: NoteDocument) {
        let previous = document
        undo.registerUndo(withTarget:self) { $0.replace(previous) }
        document = next
        guard state != nil else { return }
        saveStatus = "正在保存…"; pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:400_000_000) } catch { return }
            self?.flush()
        }
    }
    func flush() {
        pending?.cancel(); pending = nil
        guard let state, !state.notesReadOnly else { return }
        let saved = document.cleaned()
        if saved == lastSaved { saveStatus = "已自动保存"; return }
        if state.saveNotes(saved) { lastSaved = saved; saveStatus = "已自动保存" }
        else { saveStatus = "保存失败，请重试" }
    }
    func finishEditing(_ id: UUID?) {
        if let id { change { $0.entries.removeAll { $0.id == id && NoteDocument.isEmptyDraft($0) } } }
        flush()
    }

}

@MainActor private final class CommandKeyHints: ObservableObject {
    @Published var held = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pending: Task<Void,Never>?
    func start() {
        guard monitor == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pending?.cancel(); self?.held = false }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.flagsChanged) { [weak self] event in
            self?.pending?.cancel()
            if event.modifierFlags.contains(.command) {
                self?.pending = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds:350_000_000) } catch { return }
                    self?.held = true
                }
            } else { self?.held = false }
            return event
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
        pending?.cancel(); held = false
    }
}

enum NoteColors {
    static let names = ["blue","green","orange","purple","pink","red","gray"]
    static let titles = ["蓝色","绿色","橙色","紫色","粉色","红色","灰色"]
    static func nativeColor(_ name: String?) -> NSColor {
        switch name {
        case "green": return .systemGreen
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        case "pink": return .systemPink
        case "red": return .systemRed
        case "gray": return .systemGray
        default: return .systemBlue
        }
    }
    static func color(_ name: String?) -> Color {
        switch name {
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "red": return .red
        case "gray": return .gray
        default: return .blue
        }
    }
}

struct NoteEditor: View {
    let date: Date
    var initialEditingID: UUID? = nil
    var fitsWindow = false
    var initiallyExpandedTags = false
    var initiallyExpandedTools = false
    var initialScope: NoteDateScope = .day
    var initialSearch: String? = nil
    var initiallySearchAllDates = false
    var initialCompletion: NoteCompletionFilter = .all
    var initiallyHoveredDate = false
    var initialNotice: NoteNotice? = nil
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @StateObject private var draft = NoteDraft()
    @StateObject private var hints = CommandKeyHints()
    @LocalState<Bool> private var toolsExpanded = false
    @LocalState<Bool> private var tagsExpanded = false
    @State private var dateNavigationHovered = false
    @State private var lockedDateTitleWidth: CGFloat?
    @State private var dateHoverTask: Task<Void,Never>?
    @State private var searchPresented = false
    @State private var searchText = ""
    @State private var searchAllDates = false
    @State private var completionFilter: NoteCompletionFilter = .all
    @State private var pendingCompletionIDs: Set<UUID> = []
    @State private var completionTasks: [UUID:Task<Void,Never>] = [:]
    @State private var preferredInsertionDate: Date?
    @State private var activeView = false
    @State private var deferredPresentation: Task<Void,Never>?
    @FocusState private var searchFocused: Bool
    @State private var insertionPicker = false
    @State private var insertionDate = Date()
    @State private var movingIDs: Set<UUID> = []
    @State private var movingDate = Date()
    @State private var movePicker = false
    @State private var notice: NoteNotice?
    @State private var noticeDismissTask: Task<Void,Never>?
    @LocalState<NoteDateScope> private var dateScope = .day
    @LocalState<Date> private var rangeAnchor = Date()
    @LocalState<Date> private var rangeStart = Date()
    @LocalState<Date> private var rangeEnd = Date()
    @LocalState<Bool> private var rangePicker = false
    @LocalState<Set<UUID>> private var collapsibleIDs = []
    @LocalState<UUID?> private var tagID = nil
    @LocalState<Bool> private var batchMode = false
    @LocalState<Set<UUID>> private var selection = []
    @LocalState<Set<UUID>> private var collapsed = []
    @LocalState<UUID?> private var editingID = nil
    @LocalState<UUID?> private var appendedID = nil
    @LocalState<Bool> private var tagForm = false
    @LocalState<UUID?> private var renamingID = nil
    @LocalState<String> private var tagName = ""
    @LocalState<String> private var tagColor = "blue"
    @LocalState<NoteTag?> private var deletingTag = nil
    @LocalState<UUID?> private var transferID = nil
    @LocalState<Bool> private var confirmDelete = false
    @LocalState<Set<UUID>> private var pendingDelete = []
    @LocalState<Bool> private var loaded = false
    @LocalState<Bool> private var exportOptions = false
    @LocalState<NoteExport.Format> private var exportFormat = .pdf
    private var scheme: ColorScheme { state.colorScheme ?? inheritedScheme }
    private var palette: SettingsPalette { SettingsPalette(scheme) }
    private var allDates: Bool { searchAllDates || dateScope != .day }
    private var dateRange: NoteDateRange { NoteDateRange(scope:dateScope,anchor:rangeAnchor,from:rangeStart,through:rangeEnd,engine:state.engine) }
    private var effectiveRange: NoteDateRange { searchAllDates ? NoteDateRange(scope:.all,anchor:rangeAnchor,from:rangeStart,through:rangeEnd,engine:state.engine) : dateRange }
    private var query: NoteQuery { NoteQuery(range:effectiveRange,tagID:tagID,text:searchText,completion:completionFilter) }
    private var visible: [NoteEntry] { query.entries(in:draft.document,preserving:editingID,preservingIDs:pendingCompletionIDs) }
    private var resultCount: Int { query.entries(in:draft.document).count }
    private var foldable: Set<UUID> { Set(visible.map(\.id)).intersection(collapsibleIDs) }
    private var rangeTitle: String { dateRange.title(scope:dateScope,anchor:rangeAnchor,engine:state.engine) }
    private func dayTitle(_ key: String) -> String {
        let parts = key.split(separator:"-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        return state.engine.format(state.engine.date(parts[0],parts[1],parts[2]),key.prefix(4) == state.engine.key(Date()).prefix(4) ? "M月d日 EEEE" : "yyyy年M月d日 EEEE")
    }
    private var selectedIDs: Set<UUID> { selection.intersection(Set(visible.map(\.id))) }
    private var exportEntries: [NoteEntry] {
        let entries = query.entries(in:draft.document)
        return !batchMode || selectedIDs.isEmpty ? entries : entries.filter { selectedIDs.contains($0.id) }
    }
    private var allCollapsed: Bool { !foldable.isEmpty && foldable.isSubset(of:collapsed) }

    var body: some View {
        let entries = visible
        VStack(alignment:.leading,spacing:12) {
            header.zIndex(10)
            if state.notesReadOnly {
                Text("原始数据版本未知或已损坏，已保护数据。请导出 JSON 备份。").font(.caption).foregroundStyle(.red)
            }
            if searchPresented { searchBar }
            if batchMode { bulkBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:4) {
                        if entries.isEmpty {
                            VStack(spacing:8) {
                                Image(systemName:"text.book.closed").font(.system(size:25,weight:.ultraLight))
                                Text(query.hasContentFilters ? "没有符合条件的小记" : "这个日期范围还没有小记").font(.system(size:13))
                                if query.hasContentFilters {
                                    Button("清除关键词和状态筛选") { clearContentFilters() }
                                        .font(.system(size:11)).foregroundStyle(state.accent)
                                }
                            }.foregroundStyle(.tertiary).frame(maxWidth:.infinity).padding(.vertical,44)
                        }
                        ForEach(Array(entries.enumerated()),id:\.element.id) { index,entry in
                            if allDates && (index == 0 || entries[index - 1].date != entry.date) {
                                Text(dayTitle(entry.date)).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal,8).padding(.top,index == 0 ? 2 : 14).padding(.bottom,4)
                                    .frame(maxWidth:.infinity,alignment:.leading)
                            }
                            row(entry).transition(.opacity)
                        }
                    }
                    .padding(.vertical,4).padding(.bottom,42)
                }
                .frame(maxHeight:.infinity)
                .background(NoteEditingBoundary())
                .onChange(of:appendedID) { id in
                    if let id { DispatchQueue.main.async { withAnimation(reducedMotion ? nil : .easeOut(duration:0.15)) { proxy.scrollTo(id,anchor:.bottom) } } }
                }
            }
        }
        .buttonStyle(.plain).controlSize(.small).padding(.horizontal,18).padding(.vertical,14)
        .frame(width:fitsWindow ? nil : state.noteEditorSize.width,height:fitsWindow ? nil : min(state.noteEditorSize.height,state.availableHeight - 24))
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .foregroundStyle(palette.text).background(palette.backing)
        .overlay(alignment:.top) { NoteWindowDragHandle().frame(height:14).padding(.horizontal,70) }
        .environment(\.colorScheme,scheme).tint(state.accent).preferredColorScheme(state.colorScheme)
        .overlay(alignment:.bottomTrailing) {
            HStack(spacing:8) {
                if allDates {
                    Button { chooseInsertionDate() } label: {
                        HStack(spacing:4) {
                            Text("记到 " + state.engine.format(defaultInsertionDate,state.engine.calendar.isDate(defaultInsertionDate,equalTo:Date(),toGranularity:.year) ? "M月d日" : "yyyy年M月d日"))
                            Image(systemName:"chevron.down").font(.system(size:7,weight:.medium))
                        }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,9).padding(.vertical,6)
                            .background(palette.backing,in:Capsule())
                    }.buttonStyle(.plain).help("更改新增小记的日期")
                        .popover(isPresented:$insertionPicker,attachmentAnchor:.rect(.bounds),arrowEdge:.bottom) { insertionOptions }
                }
                Button { requestAddEntry() } label: {
                    Image(systemName:"plus").font(.system(size:18,weight:.light)).frame(width:36,height:36)
                        .background { Circle().fill(palette.backing); Circle().fill(state.accent.opacity(0.09)) }
                }.buttonStyle(.plain).help("记到 " + state.engine.format(defaultInsertionDate,"yyyy年M月d日") + " · ⌘N")
                    .keyboardShortcut("n",modifiers:.command).accessibilityLabel("追加一条").disabled(state.notesReadOnly)
            }.padding(18)
        }
        .overlay(alignment:.bottom) {
            if hints.held {
                Text("⌘1–6 标题   ⌘B 粗体   ⌘I 斜体   ⌘U 下划线   ⌘E 代码\n⌘N 追加   ⌘↩ 保存并继续   ⌘S 保存   ⌘Z 撤销   ⇧⌘Z 重做")
                    .font(.system(size:11)).lineSpacing(4).padding(12)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
                    .padding(.bottom,12).allowsHitTesting(false)
            }
        }
        .overlay(alignment:.bottomLeading) {
            if let notice {
                noticeView(notice).padding(.leading,18).padding(.trailing,70).padding(.bottom,allDates ? 66 : 20)
                    .transition(.move(edge:.bottom).combined(with:.opacity))
            }
        }
        .onAppear {
            activeView = true
            guard !loaded else { return }; loaded = true
            draft.begin(state); editingID = initialEditingID; tagsExpanded = initiallyExpandedTags
            toolsExpanded = initiallyExpandedTools
            rangeAnchor = date; rangeStart = date; rangeEnd = date; dateScope = initialScope
            searchPresented = initialSearch != nil || initialCompletion != .all
            searchText = initialSearch ?? ""; searchAllDates = initiallySearchAllDates; completionFilter = initialCompletion
            dateNavigationHovered = initiallyHoveredDate
            if let initialNotice { showNotice(initialNotice) }
            state.noteUndoManager = draft.undo
            state.onNoteSave = {
                (NSApp.keyWindow?.firstResponder as? GrowingNoteTextView)?.commitText()
                draft.flush()
            }
            state.onNoteAdd = { requestAddEntry() }
            state.onNoteFind = { openSearch() }
            hints.start()
        }
        .onDisappear {
            activeView = false; deferredPresentation?.cancel(); deferredPresentation = nil
            draft.finishEditing(editingID); hints.stop(); dateHoverTask?.cancel(); noticeDismissTask?.cancel(); clearCompletionFeedback()
            if state.noteUndoManager === draft.undo { state.noteUndoManager = nil; state.onNoteSave = nil; state.onNoteAdd = nil; state.onNoteFind = nil }
        }
        // Navigation actions finish editing before changing the range. Initialization must
        // preserve initialEditingID when opening a note on a different day.
        .onChange(of:dateRange) { _ in selection = []; preferredInsertionDate = nil; clearCompletionFeedback() }
        .onChange(of:tagID) { _ in finishEditing(); selection = []; clearCompletionFeedback() }
        .onChange(of:searchText) { _ in clearCompletionFeedback() }
        .onChange(of:searchAllDates) { _ in preferredInsertionDate = nil; clearCompletionFeedback() }
        .onChange(of:completionFilter) { _ in clearCompletionFeedback() }
        .onChange(of:draft.document.tags.map(\.id)) { ids in if let tagID, !ids.contains(tagID) { self.tagID = nil } }
        .onChange(of:draft.document.entries.map(\.id)) { _ in
            if case .deleted(let receipt) = notice, receipt.missingCount(in:draft.document) == 0 { dismissNotice() }
        }
        .sheet(isPresented:$tagForm) { tagFormView }
        .sheet(isPresented:$movePicker) {
            NoteMoveDatePicker(count:movingIDs.count,initialDate:movingDate,cancel:{ movePicker = false },apply:{ target in
                movePicker = false; moveEntries(movingIDs,to:target)
            }).environmentObject(state)
        }
        .sheet(item:$deletingTag) { tag in deleteTagView(tag) }
        .sheet(isPresented:$exportOptions) {
            NoteExportOptions(document:exportSource,date:rangeAnchor,allDates:effectiveRange.start == nil,tagID:tagID,format:exportFormat,initialRange:effectiveRange.start == nil ? nil : effectiveRange) { document,format,title in
                exportOptions = false
                DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NoteExport.save(document,format:format,title:title,state:state) }
            }.environmentObject(state)
        }
        .confirmationDialog("删除选中的 \(pendingDelete.count) 条小记？",isPresented:$confirmDelete) {
            Button("删除小记",role:.destructive) {
                deleteEntries(pendingDelete); pendingDelete = []
            }
        }
    }
    private var header: some View {
        ZStack(alignment:.trailing) {
            HStack(spacing:10) {
                Text("小记").font(.system(size:17,weight:.semibold)).help(draft.saveStatus).accessibilityLabel("小记，" + draft.saveStatus)
                dateNavigation
                if draft.saveStatus.hasPrefix("保存失败") {
                    Image(systemName:"exclamationmark.icloud").font(.system(size:10)).foregroundStyle(.orange).help(draft.saveStatus)
                }
                Spacer(minLength:0)
            }
            HStack(spacing:6) {
                Button { openSearch() } label: {
                    Image(systemName:"magnifyingglass").font(.system(size:12))
                        .foregroundStyle(searchPresented ? state.accent : Color.secondary).frame(width:20,height:28)
                }.help("搜索与筛选小记 · ⌘F").accessibilityLabel("搜索与筛选小记")
                if state.notePinned { pinButton }
                Button { setToolsExpanded(!toolsExpanded) } label: {
                    Image(systemName:"ellipsis").font(.system(size:13,weight:.medium))
                        .foregroundStyle(toolsExpanded ? state.accent : Color.secondary).frame(width:20,height:28)
                }.help("更多操作").accessibilityLabel("更多小记操作")
                    .popover(isPresented:$toolsExpanded,attachmentAnchor:.rect(.bounds),arrowEdge:.top) {
                        headerTools.padding(12).frame(width:220).background(palette.backing).environment(\.colorScheme,scheme)
                    }
                Button { finishEditing(); if let close = state.onNoteClose { close() } else { dismiss() } } label: {
                    Image(systemName:"xmark").font(.system(size:10)).frame(width:28,height:28)
                }.foregroundStyle(.tertiary).help("关闭 · " + draft.saveStatus).keyboardShortcut(.cancelAction)
            }
            .padding(.leading,4).background(palette.backing)
        }
        .coordinateSpace(name:"note-header")
        .overlayPreferenceValue(NoteDateAnchor.self) { anchor in
            GeometryReader { proxy in
                let overlaps = dateNavigationHovered && (anchor?.minX ?? 44) - 6 + activeDateTitleWidth + 94 > (proxy.size.width - currentTagWidth) / 2 - 6
                currentTag.opacity(overlaps ? 0 : 1).allowsHitTesting(!overlaps)
                    .position(x:proxy.size.width / 2,y:proxy.size.height / 2)
                if let anchor {
                    NoteNativeDateNavigation(title:navigationTitle,fullTitle:rangeTitle,titleWidth:activeDateTitleWidth,
                        expanded:dateNavigationHovered && !rangePicker && !toolsExpanded && !tagsExpanded,navigable:supportsDateNavigation && !rangePicker && !toolsExpanded && !tagsExpanded,
                        current:isCurrentPeriod,unit:periodUnit,currentTitle:currentPeriodTitle,background:NSColor(palette.backing),
                            open:openRangePicker,previous:{ shiftDate(-1) },next:{ shiftDate(1) },today:returnToCurrentPeriod,hovered:dateHover)
                        .frame(width:activeDateTitleWidth + 94,height:28)
                        .position(x:anchor.minX - 6 + (activeDateTitleWidth + 94) / 2,y:anchor.midY)
                }
            }
        }
        .frame(height:36).contentShape(Rectangle())
        .buttonStyle(NoteIconButtonStyle())
    }
    private var supportsDateNavigation: Bool { dateScope == .day || dateScope == .week || dateScope == .month }
    private var currentPeriodTitle: String { dateScope == .week ? "本周" : dateScope == .month ? "本月" : "今天" }
    private var periodUnit: String { dateScope == .week ? "周" : dateScope == .month ? "月" : "天" }
    private var isCurrentPeriod: Bool { dateRange.contains(state.engine.key(Date())) }
    private var dateTitleLimit: CGFloat {
        let contentWidth = state.noteEditorSize.width - 36
        let trailingWidth: CGFloat = state.notePinned ? 144 : 108
        return min(max(60,contentWidth / 2 - 78),max(40,contentWidth - trailingWidth - 138))
    }
    private var navigationTitle: String {
        let fullWidth = (rangeTitle as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:11)]).width
        guard fullWidth > dateTitleLimit, dateScope == .week || dateScope == .custom else { return rangeTitle }
        return rangeTitle.replacingOccurrences(of:#"\b\d{2}(\d{2})/"#,with:"$1/",options:.regularExpression).replacingOccurrences(of:"/0",with:"/")
    }
    private var dateTitleWidth: CGFloat {
        min(ceil((navigationTitle as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:11)]).width),dateTitleLimit)
    }
    private var activeDateTitleWidth: CGFloat { min(lockedDateTitleWidth ?? dateTitleWidth,dateTitleLimit) }
    private var dateNavigation: some View {
        Color.clear.frame(width:activeDateTitleWidth,height:28)
            .background(GeometryReader { proxy in
                Color.clear.preference(key:NoteDateAnchor.self,value:proxy.frame(in:.named("note-header")))
            })
            .accessibilityHidden(true)
            .popover(isPresented:$rangePicker,attachmentAnchor:.rect(.bounds),arrowEdge:.top) {
                NoteRangePicker(scope:dateScope,anchor:rangeAnchor,start:rangeStart,end:rangeEnd) { scope,anchor,start,end in
                    finishEditing(); searchAllDates = false; selection = []
                    dateScope = scope; rangeAnchor = anchor; rangeStart = start; rangeEnd = end; rangePicker = false
                }.environmentObject(state)
            }
    }
    private func dateHover(_ inside: Bool) {
        dateHoverTask?.cancel()
        if inside {
            if !dateNavigationHovered { lockedDateTitleWidth = dateTitleWidth }
            setTagsExpanded(false)
            withAnimation(reducedMotion ? nil : .easeInOut(duration:0.14)) { dateNavigationHovered = supportsDateNavigation }
        } else {
            dateHoverTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds:450_000_000) } catch { return }
                withAnimation(reducedMotion ? nil : .easeInOut(duration:0.14)) { dateNavigationHovered = false; lockedDateTitleWidth = nil }
            }
        }
    }
    private func shiftDate(_ delta: Int) {
        guard let next = dateScope.shiftedAnchor(rangeAnchor,by:delta,calendar:state.engine.calendar) else { return }
        finishEditing(); selection = []; searchAllDates = false; rangeAnchor = next
    }
    private func returnToCurrentPeriod() {
        guard supportsDateNavigation else { return }
        finishEditing(); selection = []; searchAllDates = false; rangeAnchor = Date()
    }
    private var headerTools: some View {
        VStack(alignment:.leading,spacing:3) {
            toolButton(allCollapsed ? "全部展开" : "全部折叠",symbol:allCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") {
                if allCollapsed { collapsed.subtract(foldable) } else { collapsed.formUnion(foldable) }
            }
            toolButton(batchMode ? "退出批量操作" : "批量操作",symbol:"checklist",disabled:state.notesReadOnly) {
                clearCompletionFeedback(); batchMode.toggle(); selection = []
            }
            Menu {
                Text(!batchMode || selectedIDs.isEmpty ? "当前视图 · \(exportEntries.count) 条" : "选中 · \(exportEntries.count) 条")
                Button("导出 PDF…") { exportFromTools(.pdf) }.disabled(state.notesReadOnly)
                Button("导出 Markdown…") { exportFromTools(.markdown) }.disabled(state.notesReadOnly)
                Button("导出 JSON…") { exportFromTools(.json) }.disabled(state.notesReadOnly)
                Divider()
                Text(state.noteStorageDescription)
                Button("全部小记 JSON 备份…") {
                    toolsExpanded = false; draft.flush()
                    presentAfterClosingPopovers(minimumDelay:150_000_000) { state.exportNotes() }
                }
            } label: { toolLabel("导出小记",symbol:"arrow.down.to.line") }
                .menuStyle(.borderlessButton).tint(palette.text).padding(.horizontal,8).help("导出当前视图或备份全部小记")
            Divider().padding(.vertical,4)
            toolButton(state.noteSimpleDisplay ? "完整显示" : "简洁显示",symbol:"text.alignleft") { state.noteSimpleDisplay.toggle() }
            toolButton("选择日期范围",symbol:"calendar") {
                presentAfterClosingPopovers(minimumDelay:150_000_000) { rangePicker = true }
            }
            toolButton(state.notePinned ? "取消独立置顶" : "独立置顶",symbol:state.notePinned ? "pin.fill" : "pin") { state.notePinned.toggle() }
            toolButton("恢复默认大小",symbol:"arrow.counterclockwise") {
                if let reset = state.onNoteResetSize { reset() } else { state.setNoteEditorSize(AppState.defaultNoteEditorSize) }
            }
        }.font(.system(size:12)).buttonStyle(.plain)
    }
    private func toolLabel(_ title: String,symbol: String) -> some View {
        Label(title,systemImage:symbol).labelStyle(.titleAndIcon).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,7)
    }
    private func toolButton(_ title: String,symbol: String,disabled: Bool = false,action: @escaping () -> Void) -> some View {
        Button {
            finishEditing(); toolsExpanded = false; action()
        } label: { toolLabel(title,symbol:symbol).padding(.horizontal,8).contentShape(Rectangle()) }
            .modifier(NoteIconHover()).disabled(disabled)
    }
    private func exportFromTools(_ format: NoteExport.Format) {
        toolsExpanded = false
        presentAfterClosingPopovers(minimumDelay:150_000_000) { export(format) }
    }
    private var pinButton: some View {
            Button { state.notePinned.toggle() } label: {
                Image(systemName:state.notePinned ? "pin.fill" : "pin").font(.system(size:12))
                    .foregroundStyle(state.notePinned ? state.accent : Color.secondary.opacity(0.65)).frame(width:22,height:22)
            }.help(state.notePinned ? "取消独立置顶" : "置顶小记 · 关闭日历仍保留")
                .accessibilityLabel(state.notePinned ? "取消置顶小记" : "置顶小记")
    }
    private var currentTagWidth: CGFloat {
        let tag = draft.document.tags.first { $0.id == tagID }
        return ceil(((tag?.name ?? "全部") as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium)]).width) + 20 + (tag == nil ? 0 : 10)
    }
    private var currentTag: some View {
        let tag = draft.document.tags.first { $0.id == tagID }
        return Button { setTagsExpanded(!tagsExpanded) } label: {
            HStack(spacing:5) {
                if let tag { Circle().fill(NoteColors.color(tag.color)).frame(width:5,height:5) }
                Text(tag?.name ?? "全部").font(.system(size:12,weight:.medium)).lineLimit(1)
            }.padding(.horizontal,10).frame(height:26)
                .background(state.accent.opacity(tagsExpanded ? 0.09 : 0.035),in:Capsule())
        }.buttonStyle(.plain).help("选择标签")
            .popover(isPresented:$tagsExpanded,attachmentAnchor:.rect(.bounds),arrowEdge:.top) {
                tabs.disabled(state.notesReadOnly).padding(12)
                    .frame(width:min(340,max(260,state.noteEditorSize.width - 36))).background(palette.backing).environment(\.colorScheme,scheme)
            }
            .accessibilityLabel("当前标签：" + (tag?.name ?? "全部"))
            .contextMenu {
                if let tag {
                    Button("重命名…") { openTagForm(tag) }
                    Button("删除标签…") { openTagDeletion(tag) }
                }
            }
    }
    private func setTagsExpanded(_ expanded: Bool) {
        if expanded { finishEditing(); closeTransientPopovers() }
        tagsExpanded = expanded
    }
    private func setToolsExpanded(_ expanded: Bool) {
        if expanded { finishEditing(); closeTransientPopovers() }
        toolsExpanded = expanded
    }
    private var tabs: some View {
        HStack(alignment:.top,spacing:6) {
            NoteTabStrip(tags:draft.document.tags,selected:tagID,accent:NSColor(state.accent),mode:reducedMotion ? "off" : state.preferences.motion,
                         select:{ finishEditing(); tagID = $0; setTagsExpanded(false) },move:{ source,target in draft.change { $0.moveTag(source,over:target) } },context:{ tag in
                let control = NoteTagContextMenu(tag:tag,
                    rename:{ openTagForm(tag) },
                    remove:{ openTagDeletion(tag) },
                    setColor:{ color in draft.change { doc in if let i = doc.tags.firstIndex(where:{ $0.id == tag.id }) { doc.tags[i].color = color } } })
                let coordinator = control.makeCoordinator(), menu = coordinator.menu()
                menu.items.first?.representedObject = coordinator
                return menu
            },wraps:true,maximumHeight:min(260,max(100,state.noteEditorSize.height - 100))).frame(maxWidth:.infinity)
            Button {
                openTagForm(nil)
            } label: { Image(systemName:"plus").font(.system(size:12,weight:.light)).frame(width:28,height:24) }
                .foregroundStyle(.secondary).buttonStyle(NoteIconButtonStyle()).help("新建标签").accessibilityLabel("新建标签")
        }
    }
    private func row(_ entry: NoteEntry) -> some View {
        NoteRow(entry:entry,tags:draft.document.tags,undo:draft.undo,
                isEditing:editingID == entry.id,isCollapsed:collapsed.contains(entry.id),
                batchMode:batchMode,isSelected:selectedIDs.contains(entry.id),allDates:false,searchText:searchText,showTags:searchPresented && (query.hasContentFilters || searchAllDates),
                edit:{ update in edit(entry.id,update:update) },
                startEditing:{
                    collapsed.remove(entry.id)
                    if editingID != entry.id { finishEditing(); editingID = entry.id }
                },endEditing:{
                    if editingID == entry.id { editingID = nil }
                    draft.finishEditing(entry.id)
                },
                toggleCollapsed:{
                    if editingID == entry.id { finishEditing() }
                    if !collapsed.insert(entry.id).inserted { collapsed.remove(entry.id) }
                },
                toggleSelected:{ if !selection.insert(entry.id).inserted { selection.remove(entry.id) } },
                delete:{ deleteEntries([entry.id]) },
                reschedule:{ destination in requestMove([entry.id],destination:destination) },
                collapseAvailability:{ value in if value { collapsibleIDs.insert(entry.id) } else { collapsibleIDs.remove(entry.id) } },
                continueWriting:{ continueEntry(entry.id) })
            .id(entry.id)
    }
    private var bulkBar: some View {
        HStack(spacing:12) {
            Button(selectedIDs.count == visible.count && !visible.isEmpty ? "取消全选" : "全选") {
                selection = selectedIDs.count == visible.count ? [] : Set(visible.map(\.id))
            }
            Text("已选 \(selectedIDs.count) 条").foregroundStyle(.secondary)
            Menu("操作") {
                Button("标记完成") { bulk { $0.isCompleted = true } }
                Button("标记未完成") { bulk { $0.isCompleted = false } }
                Menu("移到日期") {
                    Button("今天") { requestMove(selectedIDs,destination:.today) }
                    Button("明天") { requestMove(selectedIDs,destination:.tomorrow) }
                    Button("选择日期…") { requestMove(selectedIDs,destination:.custom) }
                }
                Menu("移至标签") {
                    Button("未归类") { bulk { $0.tagIDs = [] } }
                    ForEach(draft.document.tags) { tag in Button(tag.name) { bulk { $0.tagIDs = [tag.id] } } }
                }
                Button("删除…",role:.destructive) { pendingDelete = selectedIDs; confirmDelete = true }
            }.disabled(selectedIDs.isEmpty).fixedSize()
            Spacer()
            Button("完成") { batchMode = false; selection = [] }
        }.font(.system(size:11)).padding(.vertical,4)
    }
    private var tagFormView: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(renamingID == nil ? "新建标签" : "编辑标签").font(.headline)
            TextField("标签名称",text:$tagName).textFieldStyle(.roundedBorder).onSubmit { saveTag() }
            HStack(spacing:12) {
                ForEach(NoteColors.names,id:\.self) { name in
                    Button { tagColor = name } label: {
                        Circle().fill(NoteColors.color(name)).frame(width:20,height:20)
                            .overlay { if tagColor == name { Image(systemName:"checkmark").font(.system(size:10,weight:.bold)).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel(NoteColors.titles[NoteColors.names.firstIndex(of:name)!])
                }
            }
            HStack {
                Spacer(); Button("取消") { tagForm = false }
                Button("完成") { saveTag() }.buttonStyle(.borderedProminent)
                    .disabled(tagName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.document.tags.contains { $0.name == tagName.trimmingCharacters(in:.whitespacesAndNewlines) && $0.id != renamingID })
            }
        }.padding(24).frame(width:310).environment(\.colorScheme,scheme)
    }
    private func deleteTagView(_ tag: NoteTag) -> some View {
        VStack(alignment:.leading,spacing:16) {
            Text("删除「\(tag.name)」？").font(.headline)
            Text("此标签下共有 \(draft.document.entries.filter { $0.tagIDs.contains(tag.id) }.count) 条小记（包含全部日期）。")
                .font(.system(size:12))
            Picker("转移到",selection:$transferID) {
                Text("不转移，保留内容").tag(nil as UUID?)
                ForEach(draft.document.tags.filter { $0.id != tag.id }) { Text($0.name).tag(Optional($0.id)) }
            }
            Text("不转移时，小记会进入未归类；已有的其他标签关联仍会保留。不会删除正文。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("取消") { deletingTag = nil }
                Button("删除标签",role:.destructive) {
                    draft.change { $0.removeTag(tag.id,transferringTo:transferID) }
                    deletingTag = nil
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:340).environment(\.colorScheme,scheme)
    }
    private func openTagForm(_ tag: NoteTag?) {
        finishEditing(); tagsExpanded = false
        renamingID = tag?.id; tagName = tag?.name ?? ""; tagColor = tag?.color ?? "blue"
        presentAfterClosingPopovers(minimumDelay:150_000_000) { tagForm = true }
    }
    private func openTagDeletion(_ tag: NoteTag) {
        finishEditing(); tagsExpanded = false; transferID = nil
        presentAfterClosingPopovers(minimumDelay:150_000_000) { deletingTag = tag }
    }
    private func saveTag() {
        let name = tagName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, !draft.document.tags.contains(where:{ $0.name == name && $0.id != renamingID }) else { return }
        draft.change { doc in
            if let id = renamingID, let i = doc.tags.firstIndex(where:{ $0.id == id }) { doc.tags[i].name = name; doc.tags[i].color = tagColor }
            else { doc.tags.append(NoteTag(name:name,color:tagColor)) }
        }; tagForm = false
    }
    private func deleteEntries(_ ids: Set<UUID>) {
        guard !state.notesReadOnly else { return }
        finishEditing(); clearCompletionFeedback()
        let receipt = NoteDeletion(document:draft.document,ids:ids)
        guard receipt.count > 0 else { return }
        draft.change { $0.entries.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
        showNotice(.deleted(receipt))
    }
    private func requestMove(_ ids: Set<UUID>,destination: NoteMoveDestination) {
        guard !state.notesReadOnly else { return }
        finishEditing()
        let existing = ids.intersection(Set(draft.document.entries.map(\.id)))
        guard !existing.isEmpty else { return }
        switch destination {
        case .today: moveEntries(existing,to:Date())
        case .tomorrow:
            if let tomorrow = state.engine.calendar.date(byAdding:.day,value:1,to:Date()) { moveEntries(existing,to:tomorrow) }
        case .custom:
            movingIDs = existing
            let parts = draft.document.entries.first(where:{ existing.contains($0.id) })?.date.split(separator:"-").compactMap { Int($0) } ?? []
            movingDate = parts.count == 3 ? state.engine.date(parts[0],parts[1],parts[2]) : Date()
            movePicker = true
        }
    }
    private func moveEntries(_ ids: Set<UUID>,to target: Date) {
        guard !state.notesReadOnly else { return }
        finishEditing(); clearCompletionFeedback()
        var count = 0
        draft.change { count = $0.reschedule(ids,to:target,engine:state.engine) }
        selection.subtract(ids)
        showNotice(.moved(target,count))
    }
    private func showMovedDate(_ target: Date) {
        finishEditing(); searchFocused = false; searchAllDates = false
        searchText = ""; completionFilter = .all; selection = []
        dateScope = .day; rangeAnchor = target
        dismissNotice()
    }
    private func showNotice(_ value: NoteNotice) {
        noticeDismissTask?.cancel()
        withAnimation(reducedMotion ? nil : .easeOut(duration:0.18)) { notice = value }
        noticeDismissTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds:8_000_000_000) } catch { return }
            dismissNotice()
        }
    }
    private func dismissNotice() {
        noticeDismissTask?.cancel(); noticeDismissTask = nil
        withAnimation(reducedMotion ? nil : .easeOut(duration:0.18)) { notice = nil }
    }
    private func noticeView(_ value: NoteNotice) -> some View {
        HStack(spacing:10) {
            switch value {
            case .deleted(let receipt):
                Text("已删除 \(receipt.count) 条小记").lineLimit(1)
                Button("撤销") {
                    finishEditing()
                    draft.change { receipt.restore(into:&$0) }
                    dismissNotice()
                }.foregroundStyle(state.accent).help("恢复刚才删除的小记")
            case .moved(let target,let count):
                let title = state.engine.format(target,state.engine.calendar.isDate(target,equalTo:Date(),toGranularity:.year) ? "M月d日" : "yyyy年M月d日")
                Text(count > 0 ? "已将 \(count) 条移至" + title : "小记已在" + title).lineLimit(1)
                Button("查看") { showMovedDate(target) }.foregroundStyle(state.accent)
            }
            Button { dismissNotice() } label: { Image(systemName:"xmark").font(.system(size:9)).foregroundStyle(.secondary) }
                .accessibilityLabel("收起提示")
        }.font(.system(size:11)).buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,10)
            .background(.regularMaterial,in:Capsule())
            .overlay { Capsule().stroke(.primary.opacity(0.06),lineWidth:0.5) }
            .shadow(color:.black.opacity(0.06),radius:6,y:2)
    }
    private var searchBar: some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) {
                Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索小记内容",text:Binding(get:{ searchText },set:{ value in finishEditing(); selection = []; searchText = value }))
                    .textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("搜索小记内容")
                    .onExitCommand { closeSearch() }
                if !searchText.isEmpty || completionFilter != .all || searchAllDates {
                    Text("\(resultCount) 条").font(.system(size:10)).foregroundStyle(.secondary).fixedSize()
                }
                if !searchText.isEmpty {
                    Button { finishEditing(); searchText = ""; selection = []; searchFocused = true } label: {
                        Image(systemName:"xmark.circle.fill").foregroundStyle(.tertiary)
                    }.help("清除关键词").accessibilityLabel("清除搜索关键词")
                }
                Menu {
                    Picker("日期范围",selection:Binding(get:{ searchAllDates ? "all" : "current" },set:{ value in
                        finishEditing(); selection = []; searchAllDates = value == "all"
                    })) {
                        Text("当前日期范围").tag("current")
                        Text("全部日期").tag("all")
                    }
                    Divider()
                    Picker("完成状态",selection:Binding(get:{ completionFilter },set:{ value in
                        finishEditing(); selection = []; completionFilter = value
                    })) {
                        ForEach(NoteCompletionFilter.allCases,id:\.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName:"line.3.horizontal.decrease.circle").font(.system(size:15))
                        .foregroundStyle(searchAllDates || completionFilter != .all ? state.accent : Color.secondary)
                        .frame(width:22,height:22)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("筛选日期范围与完成状态").accessibilityLabel("搜索筛选条件")
                Button { closeSearch() } label: { Image(systemName:"xmark").font(.system(size:10)).frame(width:20,height:22) }
                    .help("收起搜索并清除筛选").accessibilityLabel("收起搜索并清除筛选")
            }
            if searchAllDates || completionFilter != .all {
                HStack(spacing:6) {
                    if searchAllDates {
                        searchChip("全部日期") { finishEditing(); searchAllDates = false; selection = [] }
                    }
                    if completionFilter != .all {
                        searchChip(completionFilter.title) { finishEditing(); completionFilter = .all; selection = [] }
                    }
                }
            }
        }.font(.system(size:12)).padding(.horizontal,10).padding(.vertical,8)
            .background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10))
            .overlay { RoundedRectangle(cornerRadius:10).stroke(.primary.opacity(0.05),lineWidth:0.5) }
    }
    private func searchChip(_ title: String,clear: @escaping () -> Void) -> some View {
        Button(action:clear) {
            HStack(spacing:5) {
                Text(title)
                Image(systemName:"xmark").font(.system(size:7,weight:.medium))
            }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,7).padding(.vertical,4)
                .background(.primary.opacity(0.045),in:Capsule())
        }.buttonStyle(.plain).help("清除“" + title + "”筛选").accessibilityLabel("清除“" + title + "”筛选")
    }
    private var modalPresented: Bool { tagForm || movePicker || exportOptions || deletingTag != nil || confirmDelete }
    private func closeTransientPopovers() {
        deferredPresentation?.cancel(); deferredPresentation = nil
        toolsExpanded = false; tagsExpanded = false; rangePicker = false; insertionPicker = false
        dateHoverTask?.cancel(); dateNavigationHovered = false; lockedDateTitleWidth = nil
    }
    private func presentAfterClosingPopovers(minimumDelay: UInt64 = 0,_ action: @escaping () -> Void) {
        let hadPopover = toolsExpanded || tagsExpanded || rangePicker || insertionPicker
        closeTransientPopovers()
        let delay = max(minimumDelay,hadPopover ? 150_000_000 : 0)
        if delay == 0 { action(); return }
        deferredPresentation = Task { @MainActor in
            do { try await Task.sleep(nanoseconds:delay) } catch { return }
            guard activeView, !modalPresented else { return }
            deferredPresentation = nil; action()
        }
    }
    private func openSearch() {
        guard !modalPresented else { return }
        finishEditing()
        presentAfterClosingPopovers {
            searchPresented = true
            DispatchQueue.main.async { if activeView && searchPresented { searchFocused = true } }
        }
    }
    private func openRangePicker() {
        guard !modalPresented else { return }
        finishEditing()
        presentAfterClosingPopovers { rangePicker = true }
    }
    private func closeSearch() {
        deferredPresentation?.cancel(); deferredPresentation = nil
        finishEditing(); searchFocused = false; searchPresented = false
        searchText = ""; searchAllDates = false; completionFilter = .all; selection = []
    }
    private func clearContentFilters() {
        finishEditing(); searchText = ""; completionFilter = .all; selection = []
    }
    private var insertionOptions: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("新增小记").font(.system(size:13,weight:.semibold))
            DatePicker("记到",selection:$insertionDate,in:effectiveRange.dateBounds(engine:state.engine) ?? Date.distantPast...Date.distantFuture,displayedComponents:.date)
                .environment(\.timeZone,state.engine.calendar.timeZone)
            if let tag = draft.document.tags.first(where:{ $0.id == tagID }) {
                Text("标签：" + tag.name).font(.system(size:11)).foregroundStyle(.secondary)
            }
            if query.hasContentFilters {
                Text("新增时清除关键词和状态筛选，方便继续编辑。")
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            HStack {
                Spacer()
                Button("取消") { insertionPicker = false }
                Button("开始记录") {
                    let chosen = insertionDate
                    preferredInsertionDate = chosen
                    addEntry(on:chosen)
                }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width:270).environment(\.colorScheme,scheme)
    }
    private var defaultInsertionDate: Date {
        if let preferredInsertionDate, effectiveRange.contains(state.engine.key(preferredInsertionDate)) { return preferredInsertionDate }
        return effectiveRange.insertionDate(anchor:rangeAnchor,engine:state.engine)
    }
    private func chooseInsertionDate() {
        guard !state.notesReadOnly else { return }
        let target = defaultInsertionDate
        finishEditing()
        presentAfterClosingPopovers { insertionDate = target; insertionPicker = true }
    }
    private func requestAddEntry() {
        guard !state.notesReadOnly else { return }
        addEntry(on:defaultInsertionDate)
    }
    private func addEntry(on targetDate: Date) {
        let tags = tagID.flatMap { id in draft.document.tags.contains(where:{ $0.id == id }) ? [id] : nil } ?? []
        appendEntry(NoteEntry(date:state.engine.key(targetDate),tagIDs:tags))
    }
    private func appendEntry(_ entry: NoteEntry) {
        guard !state.notesReadOnly, !modalPresented, effectiveRange.contains(entry.date) else { return }
        finishEditing()
        presentAfterClosingPopovers {
            guard effectiveRange.contains(entry.date), !state.notesReadOnly else { return }
            clearCompletionFeedback()
            searchFocused = false; searchText = ""; completionFilter = .all; selection = []
            draft.change { $0.entries.append(entry) }; editingID = entry.id; appendedID = entry.id
        }
    }
    private func continueEntry(_ id: UUID) {
        guard let next = draft.document.continuation(after:id) else { return }
        let parts = next.date.split(separator:"-").compactMap { Int($0) }
        if parts.count == 3 { preferredInsertionDate = state.engine.date(parts[0],parts[1],parts[2]) }
        draft.flush(); appendEntry(next)
    }
    private func edit(_ id: UUID,update: (inout NoteEntry) -> Void) {
        guard !state.notesReadOnly, let original = draft.document.entries.first(where:{ $0.id == id }) else { return }
        var next = original; update(&next)
        guard next != original else { return }
        next.updatedAt = Date()
        let changedCompletion = next.isCompleted != original.isCompleted
        if changedCompletion { prepareCompletionFeedback(for:next) }
        withAnimation(changedCompletion && !reducedMotion ? .easeOut(duration:0.16) : nil) {
            draft.change { document in
                if let index = document.entries.firstIndex(where:{ $0.id == id }) { document.entries[index] = next }
            }
        }
        if changedCompletion { scheduleCompletionFeedback(for:next) }
    }
    private func bulk(_ update: (inout NoteEntry) -> Void) {
        guard !state.notesReadOnly else { return }
        let ids = selectedIDs
        var changed: [NoteEntry] = []
        draft.change { doc in
            for i in doc.entries.indices where ids.contains(doc.entries[i].id) {
                let completed = doc.entries[i].isCompleted
                update(&doc.entries[i]); doc.entries[i].updatedAt = Date()
                if completed != doc.entries[i].isCompleted { prepareCompletionFeedback(for:doc.entries[i]); changed.append(doc.entries[i]) }
            }
        }
        for entry in changed { scheduleCompletionFeedback(for:entry) }
    }
    private func prepareCompletionFeedback(for entry: NoteEntry) {
        completionTasks.removeValue(forKey:entry.id)?.cancel()
        if !completionFilter.matches(entry) { pendingCompletionIDs.insert(entry.id) }
        else { pendingCompletionIDs.remove(entry.id) }
    }
    private func scheduleCompletionFeedback(for entry: NoteEntry) {
        guard pendingCompletionIDs.contains(entry.id) else { return }
        completionTasks[entry.id] = Task { @MainActor in
            do { try await Task.sleep(nanoseconds:400_000_000) } catch { return }
            withAnimation(reducedMotion ? nil : .easeOut(duration:0.16)) { _ = pendingCompletionIDs.remove(entry.id) }
            completionTasks.removeValue(forKey:entry.id)
        }
    }
    private func clearCompletionFeedback() {
        for task in completionTasks.values { task.cancel() }
        completionTasks = [:]; pendingCompletionIDs = []
    }
    private func finishEditing() {
        (NSApp.keyWindow?.firstResponder as? GrowingNoteTextView)?.commitText()
        if let window = NSApp.keyWindow, window.firstResponder is GrowingNoteTextView { window.makeFirstResponder(nil) }
        let id = editingID; editingID = nil; draft.finishEditing(id)
    }
    private var exportSource: NoteDocument {
        var document = draft.document.cleaned()
        if (batchMode && !selectedIDs.isEmpty) || query.hasContentFilters {
            let ids = Set(exportEntries.map(\.id))
            document.entries.removeAll { !ids.contains($0.id) }
        }
        return document
    }
    private func export(_ format: NoteExport.Format) {
        finishEditing(); exportFormat = format; exportOptions = true
    }
}
