import AppKit
import SwiftUI
import CalendarCore

private struct ReducedMonthPagingProbe: View {
    @ObservedObject var state: AppState
    var body: some View {
        CalendarMonthPager(month:state.month,calendar:state.engine.calendar,reduced:true,navigate:{ [displayedMonth = state.month] step in
            guard state.engine.calendar.isDate(state.month,equalTo:displayedMonth,toGranularity:.month) else { return }
            state.shift(step)
        }) {
            CalendarMonthGrid(month:$0)
        }.environmentObject(state).frame(width:420,height:800,alignment:.top)
    }
}

@MainActor func checkMonthPaging() throws {
    func precondition(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
        if !condition() { fatalError("Month paging check failed: \(message())",file:(file),line:line) }
    }
    let suite = "org.calendar.month-paging." + UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let state = AppState(defaults:defaults)
    state.preferences.material = "solid"
    state.preferences.clock = false
    state.select(state.engine.date(2026,2,12))
    let selected = state.selected
    let panel = NSPanel(contentRect:NSRect(x:40,y:40,width:420,height:800),styleMask:[.borderless],backing:.buffered,defer:false)
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    let host = NSHostingView(rootView:CalendarView(heightOverride:800).environmentObject(state))
    panel.contentView = host; panel.orderFrontRegardless()
    defer { panel.orderOut(nil); panel.contentView = nil }
    func settle(_ delay: Double = 0.08) {
        RunLoop.main.run(until:Date().addingTimeInterval(delay)); host.layoutSubtreeIfNeeded()
    }
    func descendants<T: NSView>(_ view: NSView,_ type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0,type) }
    }
    func area() -> CalendarTrackpadSwipe.Area { descendants(host,CalendarTrackpadSwipe.Area.self).first! }
    func expectMonth(_ year: Int, _ month: Int, file: StaticString = #filePath, line: UInt = #line) {
        precondition(state.engine.calendar.component(.year,from:state.month) == year,file:file,line:line)
        precondition(state.engine.calendar.component(.month,from:state.month) == month,
                     "Expected \(year)-\(month), got \(state.engine.key(state.month)); panelVisible=\(panel.isVisible)",file:file,line:line)
        precondition(state.selected == selected)
    }
    func waitForMonth(_ expected: Date) {
        precondition(waitForInterface {
            host.layoutSubtreeIfNeeded()
            return state.engine.calendar.isDate(state.month,equalTo:expected,toGranularity:.month) && area().configuration?.enabled == true
        },"Month transition must finish; expected \(state.engine.key(expected)), got \(state.engine.key(state.month))")
    }
    func image(_ name: String, view: NSView? = nil) throws -> NSBitmapImageRep {
        let source = view ?? host
        let bitmap = source.bitmapImageRepForCachingDisplay(in:source.bounds)!
        source.cacheDisplay(in:source.bounds,to:bitmap)
        if let path = ProcessInfo.processInfo.environment["CALENDAR_NOTE_TEST_OUTPUT"] {
            let directory = URL(fileURLWithPath:path,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name + ".png"))
        }
        return bitmap
    }
    func swipe(_ distance: CGFloat, cancelled: Bool = false) {
        let step = cancelled ? 0 : MonthSwipe.step(for:distance)
        let target = state.engine.calendar.date(byAdding:.month,value:step,to:state.month)!
        let expected = (1901...2100).contains(state.engine.calendar.component(.year,from:target)) ? target : state.month
        let tracker = area()
        tracker.receive(x:0,y:0,phase:.began)
        precondition(tracker.receive(x:distance,y:1,phase:.changed))
        precondition(tracker.receive(x:0,y:0,phase:cancelled ? .cancelled : .ended))
        waitForMonth(expected)
    }
    settle()
    let initialHeight = area().frame.height
    let before = try image("month-before")
    let tracker = area()
    precondition(!tracker.receive(x:0,y:0,phase:.began))
    precondition(tracker.receive(x:-120,y:2,phase:.changed))
    settle()
    let dragging = try image("month-drag-left")
    var changed = 0
    for y in stride(from:0,to:before.pixelsHigh,by:3) { for x in stride(from:0,to:before.pixelsWide,by:3) {
        let a = before.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
        let b = dragging.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
        if abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent) > 0.2 { changed += 1 }
    } }
    precondition(changed > 100, "The rendered month must move during the gesture")
    expectMonth(2026,2)
    precondition(tracker.receive(x:0,y:0,phase:.ended))
    // Momentum both during and after settling must never advance another month.
    for _ in 0..<10 { precondition(tracker.receive(x:-90,y:0,phase:.changed,momentum:true)) }
    waitForMonth(state.engine.date(2026,3,1)); expectMonth(2026,3)
    precondition(tracker.receive(x:-90,y:0,phase:.changed,momentum:true))
    precondition(area().frame.height > initialHeight, "Six-week months must keep their last row")
    _ = try image("month-next")
    swipe(120); expectMonth(2026,2)
    precondition(abs(area().frame.height - initialHeight) < 1)
    swipe(-24); expectMonth(2026,2)
    swipe(-120,cancelled:true); expectMonth(2026,2)
    precondition(!area().receive(x:2,y:20,phase:.began))
    precondition(!area().receive(x:-160,y:4,phase:.changed))
    precondition(!area().receive(x:0,y:0,phase:.ended))
    expectMonth(2026,2)
    state.month = state.engine.date(2026,12,31); settle()
    swipe(-100); expectMonth(2027,1)
    swipe(100); expectMonth(2026,12)
    state.month = state.engine.date(1901,1,1); settle()
    swipe(140); expectMonth(1901,1)
    swipe(-140); expectMonth(1901,2)
    state.month = state.engine.date(2100,12,1); settle()
    swipe(-140); expectMonth(2100,12)
    swipe(140); expectMonth(2100,11)
    // A disappearing grid must not commit a delayed page change after switching to annual view.
    area().receive(x:-100,y:0,phase:.began)
    area().receive(x:0,y:0,phase:.ended)
    state.annual = true; settle(0.32); expectMonth(2100,11)
    precondition(descendants(host,CalendarTrackpadSwipe.Area.self).isEmpty)
    state.month = state.engine.date(2026,2,1); state.annual = false
    let reducedHost = NSHostingView(rootView:ReducedMonthPagingProbe(state:state))
    panel.contentView = reducedHost; settle()
    reducedHost.layoutSubtreeIfNeeded()
    let reducedTracker = descendants(reducedHost,CalendarTrackpadSwipe.Area.self).first!
    let reducedBefore = try image("month-reduced-before",view:reducedHost)
    expectMonth(2026,2)
    reducedTracker.receive(x:-120,y:0,phase:.began); settle()
    expectMonth(2026,2)
    let reducedDuring = try image("month-reduced-during",view:reducedHost)
    precondition(reducedBefore.representation(using:.png,properties:[:]) == reducedDuring.representation(using:.png,properties:[:]),
                 "Reduce Motion must keep the grid still during the gesture")
    reducedTracker.receive(x:0,y:0,phase:.ended); expectMonth(2026,3)
    print("PASS: rendered trackpad paging, single-step momentum, short/cancelled swipe rebound, vertical scrolling, variable week rows, year rollover, range boundaries and dismissal")
    print("PASS: Reduce Motion keeps the rendered grid still and switches months immediately on release")
}
