import AppKit
import SwiftUI

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
        var accent = "blue"
        var bold = false
    }
    static func render(to directory: URL, completion: @escaping () -> Void) {
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
                state.notes[state.engine.key(state.selected)] = "今晚去散步，顺路买一束花。"
                content = AnyView(NoteEditor(date:state.selected).environmentObject(state))
                size = NSSize(width:366,height:245)
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
            DispatchQueue.main.asyncAfter(deadline:.now()+0.25) {
                save(hosting,to:directory.appendingPathComponent(job.name+".png"))
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
}
