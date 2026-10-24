import SwiftUI
import AppKit
import CalendarCore

struct NoteRow: View {
    let entry: NoteEntry
    let tags: [NoteTag]
    let undo: UndoManager
    let isEditing: Bool
    let isCollapsed: Bool
    let batchMode: Bool
    let isSelected: Bool
    let allDates: Bool
    let edit: ((inout NoteEntry) -> Void) -> Void
    let startEditing: () -> Void
    let endEditing: () -> Void
    let toggleCollapsed: () -> Void
    let toggleSelected: () -> Void
    let delete: () -> Void
    var collapseAvailability: (Bool) -> Void = { _ in }
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @LocalState<Bool> private var timeHovered = false
    @LocalState<CGFloat> private var editorHeight: CGFloat = 16
    @LocalState<Bool> private var hovering = false
    @LocalState<Bool> private var timePicker = false
    @LocalState<Bool> private var tagPicker = false
    @LocalState<CGFloat> private var swipeOffset = 0
    @LocalState<CGFloat> private var readingHeight = 0
    private var timeLabel: String? { entry.dueMinutes.map { String(format:"%02d:%02d",$0 / 60,$0 % 60) } }
    private var assignedTags: [NoteTag] { tags.filter { entry.tagIDs.contains($0.id) } }
    private var timeBinding: Binding<Date> {
        Binding(get:{
            let start = state.engine.calendar.startOfDay(for:Date())
            return start.addingTimeInterval(Double(entry.dueMinutes ?? 18 * 60) * 60)
        },set:{ value in
            let parts = state.engine.calendar.dateComponents([.hour,.minute],from:value)
            edit { $0.dueMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
        })
    }
    var body: some View {
        ZStack(alignment:.trailing) {
            if swipeOffset < 0 {
                Button { if swipeOffset <= -NoteSwipe.revealDistance { requestDelete() } } label: {
                    VStack(spacing:5) { Image(systemName:"trash"); Text("删除").font(.system(size:11)) }
                        .foregroundStyle(.white).frame(width:NoteSwipe.revealDistance).frame(maxHeight:.infinity)
                        .background(Color.red.opacity(0.85),in:RoundedRectangle(cornerRadius:7))
                }.disabled(swipeOffset > -NoteSwipe.revealDistance).accessibilityLabel("删除此条小记")
            }
            content.offset(x:swipeOffset)
        }
        .clipped()
        .overlay(alignment:.topTrailing) {
            if timeHovered, let timeLabel {
                Text(timeLabel).font(.system(size:10)).monospacedDigit().fixedSize()
                    .padding(.horizontal,6).padding(.vertical,3)
                    .background(.regularMaterial,in:Capsule())
                    .padding(.trailing,26).offset(y:firstLineTop + lineHeight + 9).allowsHitTesting(false)
            }
        }
        .background(NoteTrackpadSwipe(enabled:!isEditing && !batchMode,changed:swipeChanged,ended:swipeEnded).allowsHitTesting(false))
        .simultaneousGesture(DragGesture(minimumDistance:14).onChanged { value in
            guard !isEditing, !batchMode, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            swipeChanged(value.translation.width)
        }.onEnded { value in
            guard !isEditing, !batchMode, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            swipeEnded(value.translation.width)
        })
        .onChange(of:isEditing) { _ in swipeOffset = 0 }
        .onHover { hovering = $0 }
        .onAppear { collapseAvailability(canCollapse) }
        .onChange(of:canCollapse) { collapseAvailability($0) }
        .popover(isPresented:$timePicker) { timePickerView }
        .popover(isPresented:$tagPicker) { tagPickerView }
    }
    private var firstLineFont: NSFont {
        guard !isEditing, !isCollapsed, let block = NoteMarkdown.blocks(entry.text).first, block.kind == .heading else { return .systemFont(ofSize:13) }
        return .systemFont(ofSize:block.level == 1 ? 18 : block.level == 2 ? 16 : 14,weight:.semibold)
    }
    private var firstLineTop: CGFloat {
        !isEditing && !isCollapsed && NoteMarkdown.blocks(entry.text).first?.kind == .heading ? 3 : 0
    }
    private var lineHeight: CGFloat { ceil(NSLayoutManager().defaultLineHeight(for:firstLineFont)) }
    private var canCollapse: Bool {
        guard !entry.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return false }
        return isCollapsed || NoteMarkdown.blocks(entry.text).count > 1 || entry.text.contains("\n") ||
        max(readingHeight,isEditing ? editorHeight : 0) > lineHeight + firstLineTop + 2
    }
    private var lastLineHeight: CGFloat {
        if isCollapsed { return ceil(NSLayoutManager().defaultLineHeight(for:.systemFont(ofSize:13))) }
        let block = NoteMarkdown.blocks(entry.text).last
        let font: NSFont = block?.kind == .heading ? .systemFont(ofSize:block?.level == 1 ? 18 : block?.level == 2 ? 16 : 14,weight:.semibold) : .systemFont(ofSize:13)
        return ceil(NSLayoutManager().defaultLineHeight(for:font))
    }
    private var foldButton: some View {
        Button(action:toggleCollapsed) { Image(systemName:isCollapsed ? "chevron.down" : "chevron.up").font(.system(size:9)).frame(width:18,height:10) }
            .foregroundStyle(.secondary).opacity(hovering ? 0.65 : 0).allowsHitTesting(hovering)
            .accessibilityLabel(isCollapsed ? "展开正文" : "折叠正文")
    }
    private var content: some View {
        HStack(alignment:.top,spacing:10) {
            if batchMode {
                Button(action:toggleSelected) { Image(systemName:isSelected ? "checkmark.square.fill" : "square").foregroundStyle(.secondary) }
                    .frame(height:lineHeight).padding(.top,firstLineTop).help("选择小记")
            }
            if !state.noteSimpleDisplay {
                Button { edit { $0.isCompleted.toggle() } } label: {
                    Image(systemName:entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size:14,weight:.light))
                        .foregroundStyle(entry.isCompleted ? state.accent.opacity(0.65) : Color.secondary.opacity(0.38))
                        .frame(width:16,height:lineHeight)
                }.padding(.top,firstLineTop).help(entry.isCompleted ? "标记未完成" : "标记完成")
                    .accessibilityLabel(entry.isCompleted ? "标记未完成" : "标记完成")
            }
            VStack(alignment:.leading,spacing:3) {
                HStack(alignment:.top,spacing:6) {
                    Group {
                        if isCollapsed {
                            Text(NoteMarkdown.inline(NoteMarkdown.blocks(entry.text).first?.text ?? "空白小记"))
                                .lineLimit(1).font(.system(size:13)).onTapGesture(perform:toggleCollapsed)
                        } else if isEditing {
                            NoteTextEditor(text:Binding(get:{ entry.text },set:{ text in edit { $0.text = text } }),height:$editorHeight,undo:undo,focus:true,ended:endEditing)
                                .frame(minHeight:max(readingHeight,lineHeight))
                        } else if entry.text.isEmpty {
                            Text("写点什么…").font(.system(size:13)).foregroundStyle(.tertiary)
                                .frame(maxWidth:.infinity,alignment:.leading).onTapGesture(perform:startEditing)
                        } else {
                            NoteMarkdownView(text:entry.text).contentShape(Rectangle()).onTapGesture(perform:startEditing)
                                .background(GeometryReader { proxy in
                                    Color.clear.onAppear { readingHeight = proxy.size.height }
                                        .onChange(of:proxy.size.height) { readingHeight = $0 }
                                })
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).opacity(entry.isCompleted ? 0.55 : 1)
                        .overlay {
                            NoteRefraction(active:hovering && !isEditing && !reducedMotion && state.preferences.motion != "off",
                                           revision:entry.text + String(isCollapsed) + String(entry.isCompleted) + state.preferences.accent + String(describing:scheme))
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    if !state.noteSimpleDisplay, !entry.isCompleted, let timeLabel {
                        Button { timePicker = true } label: {
                            TimelineView(.periodic(from:.now,by:30)) { context in
                                NoteHourglass(progress:NoteDocument.timeProgress(for:entry,now:context.date,engine:state.engine))
                            }.frame(width:18,height:lineHeight)
                        }
                        .padding(.top,firstLineTop)
                        .onHover { timeHovered = $0 }
                        .help("预计完成 " + timeLabel).accessibilityLabel("预计完成 " + timeLabel)
                    }
                    NoteRowSettings(colors:assignedTags.map { NoteColors.nativeColor($0.color) },
                                    tagTitle:assignedTags.isEmpty ? "未归类" : assignedTags.map(\.name).joined(separator:"、"),
                                    categories:tags,selectedTagIDs:entry.tagIDs,chooseTag:{ id in edit { $0.tagIDs = id.map { [$0] } ?? [] } },
                                    highlighted:hovering || isEditing,lineCenter:firstLineTop + lineHeight / 2,collapsed:isCollapsed,canCollapse:canCollapse,
                                    edit:startEditing,collapse:toggleCollapsed,time:{ timePicker = true },tags:{ tagPicker = true },remove:delete)
                        .frame(width:20,height:lineHeight + firstLineTop)
                }
                if allDates {
                    Text(entry.date).font(.system(size:10)).foregroundStyle(.tertiary).frame(height:14)
                }
            }
        }
        .padding(8)
        .overlay(alignment:.bottomTrailing) {
            if canCollapse && !isEditing { foldButton.padding(.trailing,9).padding(.bottom,8 + max(0,(lastLineHeight - 10) / 2)) }
        }
        .background { if swipeOffset != 0 { SettingsPalette(state.colorScheme ?? scheme).backing } }
    }
    private var tagPickerView: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("标签").font(.system(size:12,weight:.medium))
            Button("未归类") { edit { $0.tagIDs = [] }; tagPicker = false }
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    ForEach(tags) { tag in
                        HStack(spacing:10) {
                            Button {
                                edit { $0.tagIDs = [tag.id] }; tagPicker = false
                            } label: {
                                HStack(spacing:7) { Circle().fill(NoteColors.color(tag.color)).frame(width:7,height:7); Text(tag.name); Spacer() }
                            }.buttonStyle(.plain).help("移到此标签")
                            Button {
                                edit { note in
                                    if note.tagIDs.contains(tag.id) { note.tagIDs.removeAll { $0 == tag.id } }
                                    else { note.tagIDs.append(tag.id) }
                                }
                            } label: { Image(systemName:entry.tagIDs.contains(tag.id) ? "checkmark.square.fill" : "square").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).help("保留其他标签并多选")
                        }
                    }
                }.padding(.vertical,3)
            }.frame(height:min(220,CGFloat(tags.count) * 29))
        }.font(.system(size:12)).padding(16).frame(width:210)
    }
    private var timePickerView: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("预计完成时间").font(.system(size:12,weight:.medium))
            DatePicker("",selection:timeBinding,displayedComponents:.hourAndMinute).labelsHidden()
                .environment(\.timeZone,state.engine.calendar.timeZone)
            HStack {
                Button("移除") { edit { $0.dueMinutes = nil }; timePicker = false }
                Spacer()
                Button("完成") {
                    if entry.dueMinutes == nil { edit { $0.dueMinutes = 18 * 60 } }
                    timePicker = false
                }
            }
        }.padding(18).frame(width:210)
    }
    @ViewBuilder private var rowMenu: some View {
        Button("编辑正文",action:startEditing)
        Button(isCollapsed ? "展开正文" : "折叠正文",action:toggleCollapsed)
        Button("预计完成时间…") { timePicker = true }
        Button("更换标签…") { tagPicker = true }
        Divider()
        Button("删除小记…",role:.destructive,action:delete)
    }
    private func swipeChanged(_ distance: CGFloat) { swipeOffset = max(-NoteSwipe.revealDistance,min(0,distance)) }
    private func swipeEnded(_ distance: CGFloat) {
        guard NoteSwipe.shouldConfirmDelete(distance) else { withAnimation(.easeOut(duration:0.15)) { swipeOffset = 0 }; return }
        swipeOffset = -NoteSwipe.revealDistance
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { requestDelete() }
    }
    private func requestDelete() { delete(); swipeOffset = 0 }
}
