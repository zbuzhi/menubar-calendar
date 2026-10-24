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
    var initialScope: NoteDateScope = .day
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @StateObject private var draft = NoteDraft()
    @StateObject private var hints = CommandKeyHints()
    @LocalState<Bool> private var toolsExpanded = false
    @LocalState<Bool> private var tagsExpanded = false
    @LocalState<Bool> private var headerHovered = false
    @LocalState<Bool> private var navigationHovered = false
    @LocalState<Task<Void,Never>?> private var tagDismissTask = nil
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
    private var key: String { state.engine.key(date) }
    private var scheme: ColorScheme { state.colorScheme ?? inheritedScheme }
    private var palette: SettingsPalette { SettingsPalette(scheme) }
    private var allDates: Bool { dateScope != .day }
    private var dateRange: NoteDateRange { NoteDateRange(scope:dateScope,anchor:rangeAnchor,from:rangeStart,through:rangeEnd,engine:state.engine) }
    private var visible: [NoteEntry] {
        let range = dateRange
        return draft.document.displayEntries(tagID:tagID).filter { range.contains($0.date) }
    }
    private var foldable: Set<UUID> { Set(visible.map(\.id)).intersection(collapsibleIDs) }
    private var rangeTitle: String {
        switch dateScope {
        case .day: return state.engine.format(rangeAnchor,"M月d日")
        case .month: return state.engine.format(rangeAnchor,"yyyy年M月")
        case .week,.custom: return (dateRange.start.map { String($0.suffix(5)).replacingOccurrences(of:"-",with:"/") } ?? "") + "–" + (dateRange.end.map { String($0.suffix(5)).replacingOccurrences(of:"-",with:"/") } ?? "")
        case .all: return "全部日期"
        }
    }
    private func dayTitle(_ key: String) -> String {
        let parts = key.split(separator:"-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        return state.engine.format(state.engine.date(parts[0],parts[1],parts[2]),"M月d日 EEEE")
    }
    private var selectedIDs: Set<UUID> { selection.intersection(Set(visible.map(\.id))) }
    private var exportEntries: [NoteEntry] { !batchMode || selectedIDs.isEmpty ? visible : visible.filter { selectedIDs.contains($0.id) } }
    private var allCollapsed: Bool { !foldable.isEmpty && foldable.isSubset(of:collapsed) }

    var body: some View {
        let entries = visible
        VStack(alignment:.leading,spacing:12) {
            header
                .overlay(alignment:.top) {
                    if tagsExpanded {
                        tabs.disabled(state.notesReadOnly)
                            .padding(.leading,8).padding(.vertical,8).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))
                            .overlay { RoundedRectangle(cornerRadius:14).stroke(.primary.opacity(0.06),lineWidth:0.5) }
                            .shadow(color:.black.opacity(0.1),radius:14,y:6)
                            .padding(.top,40)
                            .transition(.move(edge:.top).combined(with:.opacity))
                            .onHover { inside in navigationHovered = inside; tagHover(inside) }
                    }
                }.zIndex(10)
                .onHover { inside in headerHovered = inside; tagHover(inside) }
            if state.notesReadOnly {
                Text("原始数据版本未知或已损坏，已保护数据。请导出 JSON 备份。").font(.caption).foregroundStyle(.red)
            }
            if batchMode { bulkBar }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:4) {
                        if entries.isEmpty {
                            VStack(spacing:8) {
                                Image(systemName:"text.book.closed").font(.system(size:25,weight:.ultraLight))
                                Text("记下此刻的想法").font(.system(size:13))
                            }.foregroundStyle(.tertiary).frame(maxWidth:.infinity).padding(.vertical,44)
                        }
                        ForEach(Array(entries.enumerated()),id:\.element.id) { index,entry in
                            if allDates && (index == 0 || entries[index - 1].date != entry.date) {
                                Text(dayTitle(entry.date)).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal,8).padding(.top,index == 0 ? 2 : 14).padding(.bottom,4)
                                    .frame(maxWidth:.infinity,alignment:.leading)
                            }
                            row(entry).background(GeometryReader { proxy in
                                Color.clear.preference(key:DayCellFrames.self,value:[entry.id.uuidString:proxy.frame(in:.named("note-rows"))])
                            })
                        }
                    }
                    .coordinateSpace(name:"note-rows")
                    .backgroundPreferenceValue(DayCellFrames.self) { frames in
                        JellyHoverLayer(frames:Array(frames.values),color:NSColor(state.accent),mode:reducedMotion ? "off" : state.preferences.motion,rowStyle:true)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical,4).padding(.bottom,42)
                }
                .frame(maxHeight:.infinity)
                .background(NoteEditingBoundary())
                .onChange(of:appendedID) { id in
                    if let id { withAnimation(.easeOut(duration:0.15)) { proxy.scrollTo(id,anchor:.bottom) } }
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
            Button { addEntry() } label: {
                Image(systemName:"plus").font(.system(size:18,weight:.light)).frame(width:36,height:36)
                    .background { Circle().fill(palette.backing); Circle().fill(state.accent.opacity(0.09)) }
            }.buttonStyle(.plain).help("追加一条 · ⌘N").keyboardShortcut("n",modifiers:.command)
                .accessibilityLabel("追加一条").disabled(state.notesReadOnly).padding(18)
        }
        .overlay(alignment:.bottom) {
            if hints.held {
                Text("⌘1–6 标题   ⌘B 粗体   ⌘I 斜体   ⌘U 下划线   ⌘E 代码\n⌘N 追加   ⌘S 保存   ⌘Z 撤销   ⇧⌘Z 重做   ⌘A/X/C/V 文本操作")
                    .font(.system(size:11)).lineSpacing(4).padding(12)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
                    .padding(.bottom,12).allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            draft.begin(state); editingID = initialEditingID; tagsExpanded = initiallyExpandedTags
            rangeAnchor = date; rangeStart = date; rangeEnd = date; dateScope = initialScope
            state.noteUndoManager = draft.undo
            state.onNoteSave = {
                (NSApp.keyWindow?.firstResponder as? GrowingNoteTextView)?.commitText()
                draft.flush()
            }
            state.onNoteAdd = { addEntry() }
            hints.start()
        }
        .onDisappear {
            draft.finishEditing(editingID); hints.stop(); tagDismissTask?.cancel()
            if state.noteUndoManager === draft.undo { state.noteUndoManager = nil; state.onNoteSave = nil; state.onNoteAdd = nil }
        }
        .onChange(of:dateRange) { _ in finishEditing(); selection = [] }
        .onChange(of:tagID) { _ in finishEditing(); selection = [] }
        .onChange(of:draft.document.tags.map(\.id)) { ids in if let tagID, !ids.contains(tagID) { self.tagID = nil } }
        .popover(isPresented:$rangePicker,arrowEdge:.top) {
            NoteRangePicker(scope:dateScope,anchor:rangeAnchor,start:rangeStart,end:rangeEnd) { scope,anchor,start,end in
                finishEditing(); dateScope = scope; rangeAnchor = anchor; rangeStart = start; rangeEnd = end; rangePicker = false
            }.environmentObject(state)
        }
        .sheet(isPresented:$tagForm) { tagFormView }
        .sheet(item:$deletingTag) { tag in deleteTagView(tag) }
        .sheet(isPresented:$exportOptions) {
            NoteExportOptions(document:exportSource,date:date,allDates:allDates,tagID:tagID,format:exportFormat,initialRange:dateScope == .week || dateScope == .month || dateScope == .custom ? dateRange : nil) { document,format,title in
                exportOptions = false
                DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NoteExport.save(document,format:format,title:title,state:state) }
            }.environmentObject(state)
        }
        .confirmationDialog("删除选中的 \(pendingDelete.count) 条小记？",isPresented:$confirmDelete) {
            Button("删除小记",role:.destructive) {
                let ids = pendingDelete; draft.change { $0.entries.removeAll { ids.contains($0.id) } }; selection.subtract(ids); pendingDelete = []
            }
        }
    }
    private var header: some View {
        ZStack(alignment:.trailing) {
            HStack(spacing:10) {
                Text("小记").font(.system(size:17,weight:.semibold)).help(draft.saveStatus).accessibilityLabel("小记，" + draft.saveStatus)
                Button { rangePicker = true } label: {
                    Text(rangeTitle).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                }.buttonStyle(.plain).help("选择日期范围")
                    .opacity(toolsExpanded ? 0 : 1).allowsHitTesting(!toolsExpanded)
                if draft.saveStatus.hasPrefix("保存失败") {
                    Image(systemName:"exclamationmark.icloud").font(.system(size:10)).foregroundStyle(.orange).help(draft.saveStatus)
                }
                Spacer(minLength:0)
            }
            HStack(spacing:6) {
                if toolsExpanded {
                    headerTools.transition(.move(edge:.trailing).combined(with:.opacity))
                } else {
                    if state.notePinned { pinButton }
                    Button { setToolsExpanded(true) } label: {
                        Image(systemName:"chevron.left").font(.system(size:11,weight:.medium))
                            .foregroundStyle(.secondary).frame(width:20,height:28)
                    }
                        .onHover { inside in if inside { setToolsExpanded(true) } }
                        .accessibilityLabel("展开小记工具栏")
                        .transition(.opacity)
                }
                Button { finishEditing(); if let close = state.onNoteClose { close() } else { dismiss() } } label: {
                    Image(systemName:"xmark").font(.system(size:10)).frame(width:28,height:28)
                }.foregroundStyle(.tertiary).help("关闭 · 已自动保存").keyboardShortcut(.cancelAction)
            }
            .padding(.leading,4).background(palette.backing)
            .transition(.asymmetric(insertion:.move(edge:.trailing).combined(with:.opacity),removal:.opacity))
        }
        .overlay(alignment:.center) {
            if !toolsExpanded { currentTag }
        }
        .frame(height:36).contentShape(Rectangle())
        .onHover { inside in if !inside { setToolsExpanded(false) } }
        .buttonStyle(NoteIconButtonStyle())
    }
    private var headerTools: some View {
        HStack(spacing:8) {
            Button {
                finishEditing()
                if allCollapsed { collapsed.subtract(foldable) } else { collapsed.formUnion(foldable) }
            } label: { Image(systemName:allCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") }
                .help(allCollapsed ? "全部展开" : "全部折叠").accessibilityLabel(allCollapsed ? "全部展开" : "全部折叠")
            Button { batchMode.toggle(); selection = [] } label: {
                Image(systemName:"checklist").foregroundStyle(batchMode ? state.accent : .secondary)
            }.help("批量操作").accessibilityLabel("批量操作").disabled(state.notesReadOnly)
            Menu {
                Text(!batchMode || selectedIDs.isEmpty ? "当前视图 · \(exportEntries.count) 条" : "选中 · \(exportEntries.count) 条")
                Button("导出 PDF…") { export(.pdf) }.disabled(state.notesReadOnly)
                Button("导出 Markdown…") { export(.markdown) }.disabled(state.notesReadOnly)
                Button("导出 JSON…") { export(.json) }.disabled(state.notesReadOnly)
                Divider()
                Text(state.noteStorageDescription)
                Button("全部小记 JSON 备份…") { draft.flush(); state.exportNotes() }
            } label: { Image(systemName:"arrow.down.to.line").foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.secondary).fixedSize().padding(4).modifier(NoteIconHover()).help("导出").accessibilityLabel("导出小记")
            Button {
                finishEditing()
                if let reset = state.onNoteResetSize { reset() } else { state.setNoteEditorSize(AppState.defaultNoteEditorSize) }
            } label: { Image(systemName:"arrow.counterclockwise").font(.system(size:10)) }
                .foregroundStyle(.tertiary).help("恢复小记默认大小").accessibilityLabel("恢复小记默认大小")
            Button {
                finishEditing(); state.noteSimpleDisplay.toggle()
            } label: { Image(systemName:state.noteSimpleDisplay ? "rectangle.expand.vertical" : "text.alignleft") }
                .help(state.noteSimpleDisplay ? "切换完整显示" : "切换简洁显示")
                .accessibilityLabel(state.noteSimpleDisplay ? "切换完整显示" : "切换简洁显示")
            Button { rangePicker = true } label: { Image(systemName:"calendar") }
                .help("本周、本月或自定义范围").accessibilityLabel("选择小记日期范围")
            pinButton
        }
    }
    private var pinButton: some View {
            Button { state.notePinned.toggle() } label: {
                Image(systemName:state.notePinned ? "pin.fill" : "pin").font(.system(size:12))
                    .foregroundStyle(state.notePinned ? state.accent : Color.secondary.opacity(0.65)).frame(width:22,height:22)
            }.help(state.notePinned ? "取消独立置顶" : "置顶小记 · 关闭日历仍保留")
                .accessibilityLabel(state.notePinned ? "取消置顶小记" : "置顶小记")
    }
    private func tagHover(_ inside: Bool) {
        tagDismissTask?.cancel()
        if !inside {
            tagDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds:220_000_000)
                guard !Task.isCancelled, !headerHovered, !navigationHovered else { return }
                setTagsExpanded(false)
            }
        }
    }
    private var currentTag: some View {
        let tag = draft.document.tags.first { $0.id == tagID }
        return Button { setTagsExpanded(!tagsExpanded) } label: {
            HStack(spacing:5) {
                if let tag { Circle().fill(NoteColors.color(tag.color)).frame(width:5,height:5) }
                Text(tag?.name ?? "全部").font(.system(size:12,weight:.medium)).lineLimit(1)
            }.padding(.horizontal,10).frame(height:26)
                .background(state.accent.opacity(tagsExpanded ? 0.09 : 0.035),in:Capsule())
        }.buttonStyle(.plain).help("选择标签 · 悬停展开")
            .accessibilityLabel("当前标签：" + (tag?.name ?? "全部"))
            .onHover { inside in if inside { tagDismissTask?.cancel(); setTagsExpanded(true) } }
            .contextMenu {
                if let tag {
                    Button("重命名…") { renamingID = tag.id; tagName = tag.name; tagColor = tag.color ?? "blue"; tagForm = true }
                    Button("删除标签…") { transferID = nil; deletingTag = tag }
                }
            }
    }
    private func setTagsExpanded(_ expanded: Bool) {
        withAnimation(reducedMotion ? nil : .spring(response:0.36,dampingFraction:0.88)) { tagsExpanded = expanded }
    }
    private func setToolsExpanded(_ expanded: Bool) {
        if expanded { setTagsExpanded(false) }
        withAnimation(reducedMotion ? nil : .spring(response:0.36,dampingFraction:0.86)) { toolsExpanded = expanded }
    }
    private var tabs: some View {
        HStack(spacing:6) {
            NoteTabStrip(tags:draft.document.tags,selected:tagID,accent:NSColor(state.accent),mode:reducedMotion ? "off" : state.preferences.motion,
                         select:{ tagID = $0; setTagsExpanded(false) },move:{ source,target in draft.change { $0.moveTag(source,over:target) } },context:{ tag in
                let control = NoteTagContextMenu(tag:tag,
                    rename:{ finishEditing(); renamingID = tag.id; tagName = tag.name; tagColor = tag.color ?? "blue"; tagForm = true },
                    remove:{ finishEditing(); transferID = nil; deletingTag = tag },
                    setColor:{ color in draft.change { doc in if let i = doc.tags.firstIndex(where:{ $0.id == tag.id }) { doc.tags[i].color = color } } })
                let coordinator = control.makeCoordinator(), menu = coordinator.menu()
                menu.items.first?.representedObject = coordinator
                return menu
            },wraps:true,maximumHeight:min(260,max(100,state.noteEditorSize.height - 100))).frame(maxWidth:.infinity)
            Button {
                renamingID = nil; tagName = ""; tagColor = "blue"; tagForm = true
            } label: { Image(systemName:"plus").font(.system(size:12,weight:.light)).frame(width:28,height:24) }
                .foregroundStyle(.secondary).buttonStyle(NoteIconButtonStyle()).help("新建标签").accessibilityLabel("新建标签")
        }
    }
    private func row(_ entry: NoteEntry) -> some View {
        NoteRow(entry:entry,tags:draft.document.tags,undo:draft.undo,
                isEditing:editingID == entry.id,isCollapsed:collapsed.contains(entry.id),
                batchMode:batchMode,isSelected:selectedIDs.contains(entry.id),allDates:false,
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
                delete:{ finishEditing(); pendingDelete = [entry.id]; confirmDelete = true },
                collapseAvailability:{ value in if value { collapsibleIDs.insert(entry.id) } else { collapsibleIDs.remove(entry.id) } })
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
    private func saveTag() {
        let name = tagName.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, !draft.document.tags.contains(where:{ $0.name == name && $0.id != renamingID }) else { return }
        draft.change { doc in
            if let id = renamingID, let i = doc.tags.firstIndex(where:{ $0.id == id }) { doc.tags[i].name = name; doc.tags[i].color = tagColor }
            else { doc.tags.append(NoteTag(name:name,color:tagColor)) }
        }; tagForm = false
    }
    private func addEntry() {
        guard !state.notesReadOnly else { return }
        finishEditing()
        let entry = NoteEntry(date:state.engine.key(rangeAnchor),tagIDs:tagID.map { [$0] } ?? [])
        draft.change { $0.entries.append(entry) }; editingID = entry.id; appendedID = entry.id
    }
    private func edit(_ id: UUID,update: (inout NoteEntry) -> Void) {
        draft.change { doc in
            if let i = doc.entries.firstIndex(where:{ $0.id == id }) {
                var next = doc.entries[i]; update(&next)
                if next != doc.entries[i] { next.updatedAt = Date(); doc.entries[i] = next }
            }
        }
    }
    private func bulk(_ update: (inout NoteEntry) -> Void) {
        let ids = selectedIDs
        draft.change { doc in for i in doc.entries.indices where ids.contains(doc.entries[i].id) { update(&doc.entries[i]); doc.entries[i].updatedAt = Date() } }
    }
    private func finishEditing() {
        (NSApp.keyWindow?.firstResponder as? GrowingNoteTextView)?.commitText()
        if let window = NSApp.keyWindow, window.firstResponder is GrowingNoteTextView { window.makeFirstResponder(nil) }
        let id = editingID; editingID = nil; draft.finishEditing(id)
    }
    private var exportSource: NoteDocument {
        var document = draft.document.cleaned()
        if batchMode, !selectedIDs.isEmpty { document.entries.removeAll { !selectedIDs.contains($0.id) } }
        return document
    }
    private func export(_ format: NoteExport.Format) {
        finishEditing(); exportFormat = format; exportOptions = true
    }
}
