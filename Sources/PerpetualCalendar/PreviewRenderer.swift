import AppKit
import SwiftUI
import CalendarCore

/// Renders only this application's own views. Native backdrop capture is not a desktop screenshot.
@MainActor enum PreviewRenderer {
    private struct Job {
        let name: String
        let theme: String
        let material: String
        let tab: String
        var workspace = false
        var calendar = false
        var maximumIcons = false
        var below = false
        var note = false
        var editingNote = false
        var simpleNote = false
        var expandedTags = false
        var hoverNote = false
        var exportOptions = false
        var manyTags = false
        var weekNote = false
        var pinnedNote = false
        var rangeOptions = false
        var searchQuery: String? = nil
        var searchAllDates = false
        var completion: NoteCompletionFilter = .all
        var noteWidth: CGFloat? = nil
        var hoveredDate = false
        var crossYear = false
        var deletionNotice = false
        var moveOptions = false
        var toolsOptions = false
        var accent = "blue"
        var bold = false
    }
    static func render(to directory: URL, completion: @escaping () -> Void) {
        if ProcessInfo.processInfo.arguments.contains("--check-date-navigation"), !checkDateNavigation() { exit(1) }
        do { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) }
        catch { print("Preview directory failed: \(error)"); completion(); return }
        let defaults = UserDefaults(suiteName:"com.perpetualcalendar.preview")!
        let state = AppState(defaults:defaults)
        state.preferences = Preferences()
        state.selected = state.engine.date(2026,10,22,hour:20,minute:32,second:34)
        state.month = state.selected
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:690),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.backgroundColor = .clear; window.isOpaque = false
        var jobs = [
            Job(name:"note-tools",theme:"light",material:"solid",tab:"",note:true,toolsOptions:true),
            Job(name:"note-search-plain",theme:"light",material:"solid",tab:"",note:true,searchQuery:""),
            Job(name:"note-deleted-week",theme:"light",material:"solid",tab:"",note:true,weekNote:true,noteWidth:380,deletionNotice:true),
            Job(name:"note-date-navigation",theme:"light",material:"solid",tab:"",note:true,noteWidth:380,hoveredDate:true),
            Job(name:"note-cross-year",theme:"light",material:"solid",tab:"",note:true,weekNote:true,noteWidth:380,hoveredDate:true,crossYear:true),
            Job(name:"note-deleted",theme:"light",material:"solid",tab:"",note:true,noteWidth:380,deletionNotice:true),
            Job(name:"note-deleted-dark",theme:"dark",material:"solid",tab:"",note:true,deletionNotice:true),
            Job(name:"note-move-date",theme:"light",material:"solid",tab:"",note:true,moveOptions:true),
            Job(name:"note-search",theme:"light",material:"solid",tab:"",note:true,searchQuery:"项目",searchAllDates:true),
            Job(name:"note-search-dark",theme:"dark",material:"solid",tab:"",note:true,searchQuery:"项目",searchAllDates:true),
            Job(name:"note-search-narrow",theme:"light",material:"solid",tab:"",note:true,searchQuery:"项目",searchAllDates:true,noteWidth:380),
            Job(name:"note-incomplete",theme:"light",material:"solid",tab:"",note:true,searchQuery:"",completion:.incomplete),
            Job(name:"note-search-empty",theme:"light",material:"solid",tab:"",note:true,searchQuery:"没有匹配"),
            Job(name:"note-week",theme:"light",material:"solid",tab:"",note:true,weekNote:true),
            Job(name:"note-tags-many",theme:"light",material:"solid",tab:"",note:true,expandedTags:true,manyTags:true),
            Job(name:"note-pinned",theme:"light",material:"solid",tab:"",note:true,pinnedNote:true),
            Job(name:"note-ranges",theme:"light",material:"solid",tab:"",note:true,rangeOptions:true),
            Job(name:"note-tags",theme:"light",material:"solid",tab:"",note:true,expandedTags:true),
            Job(name:"note-hover",theme:"light",material:"solid",tab:"",note:true,hoverNote:true),
            Job(name:"note-export-options",theme:"light",material:"solid",tab:"",note:true,exportOptions:true),
            Job(name:"note-simple",theme:"light",material:"solid",tab:"",note:true,simpleNote:true),
            Job(name:"note-writing",theme:"light",material:"solid",tab:"",note:true,editingNote:true),
            Job(name:"note-editor-dark",theme:"dark",material:"solid",tab:"",note:true),
            Job(name:"note-editor",theme:"light",material:"solid",tab:"",note:true),
            Job(name:"settings-general",theme:"light",material:"solid",tab:"general"),
            Job(name:"settings-general-dark",theme:"dark",material:"solid",tab:"general"),
            Job(name:"settings-updates",theme:"light",material:"solid",tab:"updates"),
            Job(name:"settings-updates-dark",theme:"dark",material:"solid",tab:"updates"),
            Job(name:"settings-colors-narrow",theme:"dark",material:"solid",tab:"appearance",accent:"rose"),
            Job(name:"workspace-below",theme:"light",material:"solid",tab:"",workspace:true,below:true),
            Job(name:"calendar-light",theme:"light",material:"solid",tab:"",calendar:true),
            Job(name:"calendar-bold",theme:"light",material:"solid",tab:"",calendar:true,bold:true),
            Job(name:"calendar-dark",theme:"dark",material:"solid",tab:"",calendar:true),
            Job(name:"settings",theme:"light",material:"solid",tab:"appearance"),
            Job(name:"formats",theme:"light",material:"solid",tab:"formats"),
            Job(name:"formats-dark",theme:"dark",material:"solid",tab:"formats"),
            Job(name:"settings-calendar",theme:"light",material:"solid",tab:"calendar"),
            Job(name:"settings-calendar-dark",theme:"dark",material:"solid",tab:"calendar"),
            Job(name:"workspace-settings",theme:"light",material:"solid",tab:"",workspace:true),
            Job(name:"workspace-settings-dark",theme:"dark",material:"glass",tab:"",workspace:true),
            Job(name:"calendar-icons-maximum",theme:"light",material:"solid",tab:"",calendar:true,maximumIcons:true)
        ]
        for theme in ["light","dark"] {
            for material in ["glass","frosted","solid"] {
                jobs.append(Job(name:"settings-\(theme)-\(material)",theme:theme,material:material,tab:"appearance"))
            }
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of:"--preview-only"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let names = ProcessInfo.processInfo.arguments[index + 1].split(separator:",").map(String.init)
            jobs = jobs.filter { names.contains($0.name) }
        }
        func next(_ index: Int) {
            guard index < jobs.count else {
                window.orderOut(nil)
                defaults.removePersistentDomain(forName:"com.perpetualcalendar.preview")
                completion(); return
            }
            let job = jobs[index]
            state.preferences.theme = job.theme; state.preferences.material = job.material
            state.preferences.boldText = job.bold
            state.preferences.accent = job.accent
            state.preferences.iconSize = job.maximumIcons ? 16 : 6
            state.settingsPresented = job.workspace; state.settingsOnLeft = false; state.settingsWidth = 620
            state.settingsDock = job.below ? .below : .right
            state.calendarViewportHeight = job.below ? 380 : nil
            state.settingsViewportHeight = job.below ? 340 : nil
            window.appearance = NSAppearance(named:job.theme == "dark" ? .darkAqua : .aqua)
            let content: AnyView
            let size: NSSize
            if job.note {
                state.noteSimpleDisplay = job.simpleNote
                state.notePinned = job.pinnedNote
                let noteDate = job.crossYear ? state.engine.date(2026,12,31) : Date()
                let noteKey = state.engine.key(noteDate)
                var notes = NoteDocument()
                notes.entries = [
                    NoteEntry(date:noteKey,text:"## 把想法慢慢记下来\n\n1. 增加贸易条款（交货方式）的评分维护\n2. 议价报告所需的字段要能显示出来，考虑维度，供后面的核价单使用\n3. 跟进客户反馈，整理本周的工作安排\n\n**今天的重点**：把事情说明白，留出思考的时间。\n\n> 简单记录，慢慢完成。"),
                    NoteEntry(date:noteKey,text:"今晚去散步，顺路买一束花。",tagIDs:[notes.tags[1].id],dueMinutes:18 * 60,now:noteDate.addingTimeInterval(-6 * 3600)),
                    NoteEntry(date:noteKey,text:"整理本周项目进展。",tagIDs:[notes.tags[0].id],isCompleted:true)
                ]
                if job.manyTags { notes.tags += (1...14).map { NoteTag(name:"分类\($0)",color:NoteColors.names[$0 % NoteColors.names.count]) } }
                if job.searchQuery != nil {
                    notes.entries.append(NoteEntry(date:noteKey,text:"项目讨论：补充 **交付范围**，确认 `供应商编号` 与下一步安排。",tagIDs:[notes.tags[0].id]))
                    notes.entries.append(NoteEntry(date:state.engine.key(state.engine.calendar.date(byAdding:.day,value:-2,to:noteDate)!),text:"项目回顾：整理上次会议记录。",tagIDs:[notes.tags[2].id]))
                }
                if job.weekNote {
                    notes.entries.append(NoteEntry(date:state.engine.key(state.engine.calendar.date(byAdding:.day,value:-1,to:noteDate)!),text:"整理昨日的讨论，留下下一步行动。",tagIDs:[notes.tags[0].id]))
                }
                var initialNotice: NoteNotice?
                if job.deletionNotice, let id = notes.entries.first?.id {
                    initialNotice = .deleted(NoteDeletion(document:notes,ids:[id]))
                    notes.entries.removeAll { $0.id == id }
                }
                state.saveNotes(notes)
                if job.moveOptions {
                    content = AnyView(NoteMoveDatePicker(count:2,initialDate:noteDate,cancel:{},apply:{ _ in }).environmentObject(state).frame(maxWidth:.infinity,maxHeight:.infinity).background(SettingsPalette(.light).backing))
                    size = NSSize(width:340,height:210)
                } else if job.rangeOptions {
                    content = AnyView(NoteRangePicker(scope:.month,anchor:noteDate,start:noteDate,end:noteDate,apply:{ _,_,_,_ in }).environmentObject(state).frame(maxWidth:.infinity,maxHeight:.infinity).background(SettingsPalette(.light).backing))
                    size = NSSize(width:362,height:200)
                } else if job.exportOptions {
                    content = AnyView(NoteExportOptions(document:notes,date:noteDate,allDates:false,tagID:nil,format:.pdf,onExport:{ _,_,_ in }).frame(maxWidth:.infinity,maxHeight:.infinity).background(SettingsPalette(job.theme == "dark" ? .dark : .light).backing).environmentObject(state))
                    size = NSSize(width:410,height:430)
                } else {
                    if let width = job.noteWidth { state.setNoteEditorSize(NSSize(width:width,height:AppState.defaultNoteEditorSize.height)) }
                    else { state.setNoteEditorSize(AppState.defaultNoteEditorSize) }
                    content = AnyView(NoteEditor(date:noteDate,initialEditingID:job.editingNote ? notes.entries.first?.id : nil,initiallyExpandedTags:job.expandedTags,initiallyExpandedTools:job.toolsOptions,initialScope:job.weekNote ? .week : .day,initialSearch:job.searchQuery,initiallySearchAllDates:job.searchAllDates,initialCompletion:job.completion,initiallyHoveredDate:job.hoveredDate,initialNotice:initialNotice).environmentObject(state))
                    size = state.noteEditorSize
                }
            } else if job.workspace {
                content = AnyView(WorkspaceView().environmentObject(state))
                size = NSSize(width:job.below ? 620 : 1041,height:state.workspaceHeight)
            } else if job.calendar {
                content = AnyView(CalendarView().environmentObject(state))
                size = NSSize(width:420,height:state.calendarPanelHeight)
            } else {
                let width: CGFloat = job.name == "settings-colors-narrow" ? 366 : 620
                content = AnyView(SettingsView(initialTab:job.tab,width:width).environmentObject(state))
                size = NSSize(width:width,height:690)
            }
            let hosting = NSHostingView(rootView:content)
            window.contentView = hosting; hosting.frame.size = size
            window.setContentSize(size); window.orderFrontRegardless()
            if job.hoverNote {
                hosting.layoutSubtreeIfNeeded()
                func glassLayers(_ view: NSView) -> [HoverTrackingView] {
                    (view as? HoverTrackingView).map { [$0] } ?? view.subviews.flatMap { glassLayers($0) }
                }
                if let layer = glassLayers(hosting).first(where:{ $0.bounds.height > 100 }) {
                    let point = layer.convert(NSPoint(x:50,y:20),to:nil)
                    if let event = NSEvent.mouseEvent(with:.mouseMoved,location:point,modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:0,pressure:0) { layer.mouseMoved(with:event) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {
                let popup = job.toolsOptions || job.expandedTags ? NSApp.windows.first(where:{ $0 !== window && $0.isVisible && $0.contentView != nil })?.contentView : nil
                save(popup ?? hosting,to:directory.appendingPathComponent(job.name+".png"))
                next(index+1)
            }
        }
        next(0)
    }
    private static func save(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { print("Preview bitmap failed"); return }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { return }
        do { try data.write(to:url); print("Rendered: \(url.path)") } catch { print("Preview write failed: \(error)") }
    }

    private static func checkDateNavigation() -> Bool {
        let area = NoteNativeDateNavigation.Area(frame:NSRect(x:0,y:0,width:144,height:28))
        var nextCount = 0, previousCount = 0, todayCount = 0, openCount = 0
        func configuration(_ title: String) -> NoteNativeDateNavigation {
            NoteNativeDateNavigation(title:title,fullTitle:title,titleWidth:50,expanded:true,navigable:true,current:false,
                unit:"天",currentTitle:"今天",background:.windowBackgroundColor,open:{ openCount += 1 },
                previous:{ previousCount += 1 },next:{ nextCount += 1 },today:{ todayCount += 1 },hovered:{ _ in })
        }
        area.configure(configuration("10月9日"))
        let buttons = area.subviews.compactMap { $0 as? NSButton }
        guard buttons.count == 4 else { print("FAIL: native date button count"); return false }
        for button in buttons {
            let point = NSPoint(x:button.frame.midX,y:button.frame.midY)
            guard area.hitTest(point) === button else { print("FAIL: native date button hit testing"); return false }
        }
        let nextFrame = buttons[2].frame
        buttons[2].performClick(nil)
        area.configure(configuration("10月10日"))
        guard buttons[2].frame == nextFrame else { print("FAIL: date button moved under pointer"); return false }
        buttons[2].performClick(nil); buttons[1].performClick(nil); buttons[3].performClick(nil); buttons[0].performClick(nil)
        area.stop()
        guard nextCount == 2, previousCount == 1, todayCount == 1, openCount == 1 else {
            print("FAIL: native date button actions"); return false
        }
        print("Passed: native date buttons receive clicks, retain positions and support repeated next/previous/today actions")
        return true
    }
}
