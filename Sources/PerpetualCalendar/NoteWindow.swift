import AppKit
import SwiftUI

@MainActor final class NoteHostingView<Content: View>: NSHostingView<Content> {
    override var preservesContentDuringLiveResize: Bool { false }
}

@MainActor final class NoteWindowController: NSObject, NSWindowDelegate {
    let panel: CalendarPanel
    private let state: AppState
    private var day: String?
    private var applyingSize = false
    private weak var calendarWindow: NSWindow?
    private(set) var anchorPanel: NSPanel?
    private var calendarObserver: NSObjectProtocol?
    init(state: AppState) {
        self.state = state
        panel = CalendarPanel(contentRect:NSRect(origin:.zero,size:state.noteEditorSize),
                              styleMask:[.titled,.resizable,.fullSizeContentView,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        panel.title = "小记"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.level = .statusBar
        panel.contentMinSize = NSSize(width:380,height:300)
        panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        for button: NSWindow.ButtonType in [.closeButton,.miniaturizeButton,.zoomButton] { panel.standardWindowButton(button)?.isHidden = true }
        panel.delegate = self
        updatePin()
    }
    func show(date: Date,near calendar: NSWindow) {
        calendarWindow = calendar
        if calendarObserver == nil {
            calendarObserver = NotificationCenter.default.addObserver(forName:NSWindow.didMoveNotification,object:calendar,queue:.main) { [weak self,weak calendar] _ in
                MainActor.assumeIsolated { if let calendar { self?.updateAnchor(near:calendar) } }
            }
        }
        let key = state.engine.key(date)
        if day != key || panel.contentView == nil {
            state.onNoteSave?(); day = key
            let host = NoteHostingView(rootView:NoteEditor(date:date,fitsWindow:true).ignoresSafeArea().environmentObject(state))
            host.sizingOptions = []; panel.contentView = host
        }
        panel.appearance = state.preferences.theme == "system" ? nil : NSAppearance(named:state.preferences.theme == "dark" ? .darkAqua : .aqua)
        guard !panel.isVisible else { panel.makeKeyAndOrderFront(nil); updateAnchor(near:calendar); return }
        let screen = state.notePinned ? (state.noteWindowOrigin.flatMap { point in NSScreen.screens.first { $0.visibleFrame.contains(point) } } ?? calendar.screen ?? NSScreen.main) : (calendar.screen ?? NSScreen.main)
        let bounds = screen?.visibleFrame ?? NSRect(x:0,y:0,width:1000,height:800)
        applyingSize = true
        panel.setContentSize(NSSize(width:min(state.noteEditorSize.width,bounds.width - 24),height:min(state.noteEditorSize.height,bounds.height - 24)))
        var frame = panel.frame
        let beside = calendar.frame.maxX + 10
        frame.origin.x = beside + frame.width <= bounds.maxX ? beside : max(bounds.minX + 12,calendar.frame.minX - frame.width - 10)
        frame.origin.y = min(bounds.maxY - frame.height - 12,max(bounds.minY + 12,calendar.frame.maxY - frame.height))
        if state.notePinned, let origin = state.noteWindowOrigin {
            frame.origin.x = min(max(origin.x,bounds.minX + 12),bounds.maxX - frame.width - 12)
            frame.origin.y = min(max(origin.y,bounds.minY + 12),bounds.maxY - frame.height - 12)
        }
        panel.setFrame(frame,display:true); applyingSize = false
        panel.makeKeyAndOrderFront(nil); updateAnchor(near:calendar)
    }
    func updatePin() {
        panel.collectionBehavior = state.notePinned ? [.canJoinAllSpaces,.fullScreenAuxiliary] : [.moveToActiveSpace,.fullScreenAuxiliary]
        if state.notePinned, panel.isVisible { state.setNoteWindowOrigin(panel.frame.origin) }
    }
    func windowDidResignKey(_ notification: Notification) {
        if panel.firstResponder is GrowingNoteTextView { panel.makeFirstResponder(nil); state.onNoteSave?() }
    }
    func windowDidMove(_ notification: Notification) {
        if let calendarWindow { updateAnchor(near:calendarWindow) }
        if !applyingSize, state.notePinned, panel.isVisible { state.setNoteWindowOrigin(panel.frame.origin) }
    }
    func hide() {
        panel.makeFirstResponder(nil); state.onNoteSave?()
        anchorPanel?.orderOut(nil)
        panel.orderOut(nil); panel.contentView = nil; day = nil
    }
    func updateAnchor(near calendar: NSWindow) {
        guard panel.isVisible, calendar.isVisible else { anchorPanel?.orderOut(nil); return }
        let pointsLeft = panel.frame.midX >= calendar.frame.midX
        let width: CGFloat = 11, height: CGFloat = 22
        let centerY = min(panel.frame.maxY - 40,max(panel.frame.minY + 40,calendar.frame.midY))
        let arrow = anchorPanel ?? NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        if anchorPanel == nil {
            arrow.isOpaque = false; arrow.backgroundColor = .clear; arrow.hasShadow = false
            arrow.ignoresMouseEvents = true; arrow.isReleasedWhenClosed = false
            arrow.level = panel.level; panel.addChildWindow(arrow,ordered:.above); anchorPanel = arrow
        }
        arrow.appearance = panel.appearance
        let view = (arrow.contentView as? NoteAnchorShape) ?? NoteAnchorShape(frame:NSRect(x:0,y:0,width:width,height:height))
        view.pointsLeft = pointsLeft
        view.dark = panel.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua
        if arrow.contentView !== view { arrow.contentView = view }; view.needsDisplay = true
        arrow.setFrame(NSRect(x:pointsLeft ? panel.frame.minX - width + 1 : panel.frame.maxX - 1,y:centerY - height / 2,width:width,height:height),display:true)
        arrow.orderFrontRegardless()
    }
    deinit { if let calendarObserver { NotificationCenter.default.removeObserver(calendarObserver) } }
    func resetSize() {
        applyingSize = true; state.setNoteEditorSize(AppState.defaultNoteEditorSize)
        var frame = panel.frame
        let oldTop = frame.maxY
        let content = NSRect(origin:.zero,size:AppState.defaultNoteEditorSize)
        frame.size = panel.frameRect(forContentRect:content).size; frame.origin.y = oldTop - frame.height
        if let screen = panel.screen {
            frame.origin.x = min(max(frame.minX,screen.visibleFrame.minX),screen.visibleFrame.maxX - frame.width)
            frame.origin.y = max(screen.visibleFrame.minY,frame.minY)
        }
        panel.setFrame(frame,display:true); applyingSize = false
    }
    func windowDidResize(_ notification: Notification) {
        guard let host = panel.contentView else { return }
        host.needsLayout = true; host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard !applyingSize, !panel.inLiveResize else { return }
        state.setNoteEditorSize(host.bounds.size)
        if let calendarWindow { updateAnchor(near:calendarWindow) }
    }
    func windowDidEndLiveResize(_ notification: Notification) { if let size = panel.contentView?.bounds.size { state.setNoteEditorSize(size) } }
    func windowWillClose(_ notification: Notification) { state.onNoteSave?(); state.noteEditorDate = nil }
}

@MainActor enum NoteSaveDialog {
    private(set) static var isPresenting = false
    /// Calendar panels use status-bar level. A normal-level modal save dialog would be hidden behind them.
    static func prepare(_ panel: NSSavePanel,near owner: NSWindow?) {
        panel.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue + 2)
        panel.setContentSize(NSSize(width:640,height:430))
        let visible = (owner?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:1000,height:800)
        panel.setFrameOrigin(NSPoint(x:visible.midX - panel.frame.width / 2,y:visible.midY - panel.frame.height / 2))
    }
    static func run(_ panel: NSSavePanel,near requestedOwner: NSWindow? = nil) -> NSApplication.ModalResponse {
        isPresenting = true
        defer { isPresenting = false }
        let owner = requestedOwner ?? NSApp.keyWindow
        owner?.makeFirstResponder(nil)
        prepare(panel,near:owner)
        NSApp.activate(ignoringOtherApps:true)
        panel.makeKeyAndOrderFront(nil)
        return panel.runModal()
    }
}

private final class NoteAnchorShape: NSView {
    var pointsLeft = true
    var dark = false
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath()
        p.move(to:NSPoint(x:pointsLeft ? bounds.maxX : bounds.minX,y:0))
        p.line(to:NSPoint(x:pointsLeft ? bounds.minX : bounds.maxX,y:bounds.midY))
        p.line(to:NSPoint(x:pointsLeft ? bounds.maxX : bounds.minX,y:bounds.maxY))
        p.close(); NSColor(white:dark ? 0.075 : 0.98,alpha:1).setFill(); p.fill()
    }
}
