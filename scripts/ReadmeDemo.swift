import AppKit
import SwiftUI
import CalendarCore

// Render the app's own views with an isolated preferences domain. This is a
// component demonstration, not a desktop recording or OS input automation.
@MainActor final class DemoControl: ObservableObject {
    @Published var tab = "appearance"
    @Published var caption = "移动到日期上，感受连续的果冻滑块"
}

struct DemoScene: View {
    @ObservedObject var state: AppState
    @ObservedObject var control: DemoControl
    var body: some View {
        VStack(spacing:14) {
            HStack {
                Text("不知时日历").font(.system(size:21,weight:.semibold))
                Text("macOS 菜单栏万年历").font(.system(size:12)).foregroundStyle(.secondary)
                Spacer()
                Text("原生界面演示").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,8)
            HStack(spacing:0) {
                CalendarView(embedded:true,heightOverride:750)
                Rectangle().fill(.primary.opacity(0.09)).frame(width:1,height:720)
                SettingsView(initialTab:control.tab,embedded:true,width:500,height:750).id(control.tab)
            }
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius:22))
            HStack {
                Circle().fill(state.accent).frame(width:6,height:6)
                Text(control.caption).font(.system(size:13,weight:.medium))
                Spacer()
                Text("修改即时生效").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(.horizontal,8)
        }
        .padding(20)
        .frame(width:961,height:868)
        .background(Color(nsColor:state.preferences.theme == "dark" ? NSColor(calibratedWhite:0.045,alpha:1) : NSColor(calibratedRed:0.91,green:0.94,blue:0.97,alpha:1)))
        .environmentObject(state)
        .environment(\.colorScheme,state.preferences.theme == "dark" ? .dark : .light)
        .preferredColorScheme(state.preferences.theme == "dark" ? .dark : .light)
    }
}

final class DemoPointer: NSView {
    var point = CGPoint(x:-30,y:-30) { didSet { needsDisplay = true } }
    var clicking = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        if clicking {
            NSColor.systemBlue.withAlphaComponent(0.2).setFill()
            NSBezierPath(ovalIn:NSRect(x:point.x-14,y:point.y-14,width:28,height:28)).fill()
        }
        let image = NSCursor.arrow.image
        image.draw(in:NSRect(x:point.x,y:point.y,width:17,height:25),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}

@MainActor final class ReadmeDemo: NSObject, NSApplicationDelegate {
    let directory: URL
    let defaults = UserDefaults(suiteName:"org.menubar-calendar.readme-demo")!
    var state: AppState!
    let control = DemoControl()
    var window: NSWindow!
    var host: NSHostingView<DemoScene>!
    let pointer = DemoPointer()
    var timer: Timer?
    var started = 0.0
    var frame = 0
    var stage = -1
    var activity: NSObjectProtocol?
    var captures: [[String:Any]] = []
    let fps = 15.0
    init(directory:URL) { self.directory = directory; super.init() }
    func applicationDidFinishLaunching(_ notification:Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options:[.userInitiatedAllowingIdleSystemSleep,.latencyCritical],reason:"Render README component demonstration")
        defaults.removePersistentDomain(forName:"org.menubar-calendar.readme-demo")
        state = AppState(defaults:defaults)
        state.preferences.theme = "light"
        state.preferences.material = "solid"
        state.preferences.motion = "jelly"
        state.preferences.accent = "blue"
        state.selected = state.engine.date(2026,10,23,hour:20,minute:32,second:34)
        state.month = state.selected
        state.saveNotes(NoteDocument())
        state.availableHeight = 1000
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:961,height:868),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        host = NSHostingView(rootView:DemoScene(state:state,control:control))
        window.contentView = host
        pointer.frame = host.bounds; pointer.autoresizingMask = [.width,.height]
        host.addSubview(pointer)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.7) { self.begin() }
    }
    func bitmap(_ view:NSView, to url:URL) {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(bounds.width),pixelsHigh:Int(bounds.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size = bounds.size
        view.cacheDisplay(in:bounds,to:bitmap)
        try! bitmap.representation(using:.png,properties:[:])!.write(to:url)
    }
    func begin() {
        // Save clean native calendar views for the static cover.
        saveCalendar(theme:"light",name:"calendar-light.png")
        saveCalendar(theme:"dark",name:"calendar-dark.png")
        state.preferences.theme = "light"
        started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:1/fps,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func saveCalendar(theme:String,name:String) {
        let snapshotState = AppState(defaults:defaults)
        snapshotState.preferences = state.preferences
        snapshotState.preferences.theme = theme
        snapshotState.preferences.accent = theme == "dark" ? "teal" : "blue"
        snapshotState.selected = state.selected; snapshotState.month = state.month
        snapshotState.availableHeight = 1000
        let view = NSHostingView(rootView:CalendarView(heightOverride:750).environmentObject(snapshotState).environment(\.colorScheme,theme == "dark" ? .dark : .light))
        let snapshot = NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:750),styleMask:[.borderless],backing:.buffered,defer:false)
        snapshot.contentView = view; snapshot.isReleasedWhenClosed = false
        snapshot.appearance = NSAppearance(named:theme == "dark" ? .darkAqua : .aqua)
        snapshot.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date(timeIntervalSinceNow:0.2))
        bitmap(view,to:directory.appendingPathComponent(name))
        snapshot.orderOut(nil)
    }
    func hover(_ view:NSView) -> HoverTrackingView? {
        if let view = view as? HoverTrackingView { return view }
        for child in view.subviews { if let match = hover(child) { return match } }
        return nil
    }
    func tick() {
        let t = ProcessInfo.processInfo.systemUptime-started
        if t >= 21 {
            timer?.invalidate(); window.orderOut(nil)
            defaults.removePersistentDomain(forName:"org.menubar-calendar.readme-demo")
            try! JSONSerialization.data(withJSONObject:captures).write(to:directory.appendingPathComponent("frames.json"))
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            print("Rendered \(frame) native frames"); fflush(stdout)
            exit(0)
        }
        let next: Int
        switch t {
        case ..<4: next=0
        case ..<5.3: next=1
        case ..<6.6: next=2
        case ..<7.9: next=3
        case ..<9.6: next=4
        case ..<11: next=5
        case ..<12.2: next=6
        case ..<13.5: next=7
        case ..<14.8: next=8
        case ..<16: next=9
        case ..<17.2: next=10
        case ..<18.4: next=11
        default: next=12
        }
        let changed = next != stage
        if changed {
            stage=next
            if stage != 0, let layer=hover(host), let event=NSEvent.mouseEvent(with:.mouseMoved,location:.zero,modifierFlags:[],timestamp:t,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0) { layer.mouseExited(with:event) }
            withAnimation(.spring(response:0.28,dampingFraction:0.82)) {
                switch stage {
                case 0: control.caption="移动到日期上，感受连续的果冻滑块"
                case 1: state.preferences.accent="purple"; control.caption="12 种主题色，修改时左侧月历同步变化"
                case 2: state.preferences.accent="teal"
                case 3: state.preferences.accent="rose"
                case 4: state.preferences.theme="dark";control.caption="浅色 / 深色，随习惯自由切换"
                case 5: state.preferences.theme="light"
                case 6: control.tab="calendar";control.caption="显示什么，由你决定"
                case 7: state.preferences.zodiac="hidden"
                case 8: state.preferences.termIcons=false;control.caption="星座、节气全部隐藏时，自动收紧日期行"
                case 9: state.preferences.zodiac="icon";state.preferences.termIcons=true
                case 10: state.preferences.lunar=false;control.caption="农历显示，也可以随时开关"
                case 11: state.preferences.lunar=true
                default: control.tab="appearance";state.preferences.accent="blue";control.caption="日历与设置并排展示，改动一眼可见"
                }
            }
        }
        pointer.clicking = changed && stage != 0 && stage != 6
        if stage == 0 {
            let phase=t/3.5*2*Double.pi
            pointer.point=CGPoint(x:230+120*cos(phase),y:285+90*sin(phase))
            if let layer=hover(host) {
                let point = host.convert(pointer.point,to:nil)
                if let event=NSEvent.mouseEvent(with:.mouseMoved,location:point,modifierFlags:[],timestamp:t,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0) { layer.mouseMoved(with:event) }
            }
        } else {
            let positions:[Int:CGPoint]=[1:CGPoint(x:729,y:304),2:CGPoint(x:802,y:304),3:CGPoint(x:504,y:359),4:CGPoint(x:834,y:234),5:CGPoint(x:694,y:234),6:CGPoint(x:596,y:134),7:CGPoint(x:539,y:233),8:CGPoint(x:894,y:278),9:CGPoint(x:691,y:233),10:CGPoint(x:894,y:494),11:CGPoint(x:894,y:494),12:CGPoint(x:506,y:134)]
            pointer.point=positions[stage] ?? .zero
        }
        bitmap(host,to:directory.appendingPathComponent(String(format:"frame-%04d.png",frame)))
        captures.append(["time":t,"stage":stage,"file":String(format:"frame-%04d.png",frame)])
        frame += 1
    }
}

@main enum ReadmeDemoMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let delegate=ReadmeDemo(directory:directory);app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
