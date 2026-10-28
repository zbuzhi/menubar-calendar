import AppKit
import SwiftUI
import Carbon
import CalendarCore
import Combine

final class CalendarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var statusItem: NSStatusItem!
    var noteWindow: NoteWindowController?
    var panel: CalendarPanel!
    var stateSubscription: AnyCancellable?
    var globalClickMonitor: Any?
    var layoutPending = false
    var timer: Timer?
    var workspaceObserver: NSObjectProtocol?
    var dateObserver: NSObjectProtocol?
    var keyMonitor: Any?
    var hotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    var lastSelectionDay: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of:"--render-preview"), ProcessInfo.processInfo.arguments.count > index + 1 {
            NSApp.setActivationPolicy(.accessory)
            PreviewRenderer.render(to:URL(fileURLWithPath:ProcessInfo.processInfo.arguments[index + 1],isDirectory:true)) { NSApp.terminate(nil) }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        state.softwareUpdater.start()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        statusItem.button?.toolTip = AppBrand.name + " · ⌃⌥空格打开 · 右键复制"
        panel = CalendarPanel(contentRect:NSRect(x:0,y:0,width:420,height:700),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = AppBrand.name
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        panel.contentView = TransparentHostingView(rootView:WorkspaceView().environmentObject(state))
        state.onNotePresentationChange = { [weak self] in self?.syncNoteWindow() }
        state.onNoteClose = { [weak self] in self?.state.noteEditorDate = nil }
        state.onNotePinChange = { [weak self] in
            guard let self else { return }
            self.noteWindow?.updatePin()
            if self.state.notePinned { self.hidePanel() }
        }
        state.onNoteResetSize = { [weak self] in self?.noteWindow?.resetSize() }
        state.onSettings = { [weak self] in self?.toggleSettings() }
        state.onShowSettings = { [weak self] in self?.showSettings() }
        state.onPreferencesChange = { [weak self] in self?.updateStatus() }
        stateSubscription = state.objectWillChange.sink { [weak self] _ in self?.scheduleLayout() }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleOutsideClick(at:NSEvent.mouseLocation)
            }
        }
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        if let timer { RunLoop.main.add(timer,forMode:.common) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        dateObserver = NotificationCenter.default.addObserver(forName:.NSCalendarDayChanged,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        installEditMenu()
        installKeyboard()
        registerHotkey()
        if ProcessInfo.processInfo.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { self.showPopover() } }
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
    }
    func updateStatus() {
        let now = Date()
        let value = state.render(state.preferences.menuTemplate,at:now)
        statusItem.button?.title = value.isEmpty ? AppBrand.name : value
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize:12,weight:state.usesBoldText ? .semibold : .regular)
        statusItem.button?.setAccessibilityLabel("日历，"+value)
        let today = state.engine.key(now)
        if let lastSelectionDay, lastSelectionDay != today, state.engine.key(state.selected) == lastSelectionDay { state.today() }
        lastSelectionDay = today
    }
    var statusItemFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds,to:nil))
    }
    func handleOutsideClick(at point: NSPoint) {
        guard !state.pinned, !NoteSaveDialog.isPresenting else { return }
        // The status-item action handles this click on mouse-up. Closing here
        // on mouse-down would make that action reopen the panel.
        guard statusItemFrame?.contains(point) != true else { return }
        hidePanel()
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        togglePopover()
    }
    func togglePopover() { if panel.isVisible { hidePanel() } else { showPopover() } }
    func showPopover() {
        state.refreshHolidays()
        layoutPanel()
        panel.makeKeyAndOrderFront(nil)
        noteWindow?.updateAnchor(near:panel)
    }
    func syncNoteWindow() {
        if let date = state.noteEditorDate {
            if noteWindow == nil { noteWindow = NoteWindowController(state:state) }
            noteWindow?.show(date:date,near:panel)
        } else { noteWindow?.hide() }
    }
    func hidePanel() { state.onNoteSave?(); panel.orderOut(nil); noteWindow?.updateAnchor(near:panel); state.settingsPresented = false; if !state.notePinned { state.noteEditorDate = nil } }
    func toggleSettings() {
        state.settingsPresented.toggle()
        showPopover()
    }
    func showSettings() {
        state.settingsPresented = true
        showPopover()
    }
    func scheduleLayout() {
        guard !layoutPending else { return }
        layoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutPending = false
            if self.panel?.isVisible == true { self.layoutPanel() }
        }
    }
    func layoutPanel() {
        guard let button = statusItem.button, let statusWindow = button.window,
              let screen = statusWindow.screen ?? NSScreen.main else { return }
        // Match native menus/text fields to SwiftUI, rather than the system's opposite theme.
        let desiredAppearance = state.preferences.theme == "system" ? nil : NSAppearance(named:state.preferences.theme == "dark" ? .darkAqua : .aqua)
        if panel.appearance?.name != desiredAppearance?.name { panel.appearance = desiredAppearance }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds,to:nil))
        let visible = screen.visibleFrame
        if state.availableHeight != visible.height { state.availableHeight = visible.height }
        let placement = WorkspacePlacement(anchor:anchor,visibleFrame:visible,calendarHeight:state.calendarPanelHeight,settings:state.settingsPresented)
        if state.settingsOnLeft != placement.settingsOnLeft { state.settingsOnLeft = placement.settingsOnLeft }
        if state.settingsWidth != placement.settingsWidth { state.settingsWidth = placement.settingsWidth }
        if state.settingsDock != placement.dock { state.settingsDock = placement.dock }
        if state.calendarViewportHeight != placement.calendarHeight { state.calendarViewportHeight = placement.calendarHeight }
        if state.settingsViewportHeight != placement.settingsHeight { state.settingsViewportHeight = placement.settingsHeight }
        if panel.frame != placement.frame { panel.setFrame(placement.frame,display:true) }
        panel.invalidateShadow()
    }
    func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        add(menu,"打开日历",#selector(openCalendar))
        add(menu,"复制当前显示格式",#selector(copyCurrent))
        add(menu,"复制通用格式",#selector(copyStandard))
        menu.addItem(.separator())
        add(menu,"设置…",#selector(openSettings))
        let updateItem = NSMenuItem(title:"检查软件更新…",action:#selector(checkSoftwareUpdates),keyEquivalent:"")
        updateItem.target = self
        updateItem.isEnabled = state.softwareUpdater.canCheck
        menu.addItem(updateItem)
        add(menu,"退出" + AppBrand.name,#selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    func add(_ menu:NSMenu,_ title:String,_ selector:Selector) { let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item) }
    @objc func openCalendar() { showPopover() }
    @objc func openSettings() { showSettings() }
    @objc func checkSoftwareUpdates() { state.openSettings(tab:"updates"); state.softwareUpdater.check() }
    @objc func copyCurrent() { state.copy(state.preferences.menuTemplate) }
    @objc func copyStandard() { state.copy(state.preferences.copyTemplate) }
    @objc func quit() { state.onNoteSave?(); NSApp.terminate(nil) }
    private var editingUndoManager: UndoManager? {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager }
        return state.noteUndoManager ?? NSApp.keyWindow?.firstResponder?.undoManager
    }
    @objc func editUndo(_ sender: Any?) { editingUndoManager?.undo() }
    @objc func editRedo(_ sender: Any?) { editingUndoManager?.redo() }
    @objc func addNote(_ sender: Any?) { state.onNoteAdd?() }
    @objc func findNote(_ sender: Any?) { state.onNoteFind?() }
    @objc func saveNote(_ sender: Any?) { state.onNoteSave?() }

    func installEditMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title:AppBrand.name)
        let quitItem = NSMenuItem(title:"退出" + AppBrand.name,action:#selector(quit),keyEquivalent:"q")
        quitItem.target = self; applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu; menu.addItem(applicationItem)
        let root = NSMenuItem(title:"编辑",action:nil,keyEquivalent:"")
        let edit = NSMenu(title:"编辑")
        for (title, action, key, shift) in [
            ("撤销", "editUndo:", "z", false), ("重做", "editRedo:", "z", true),
            ("剪切", "cut:", "x", false), ("复制", "copy:", "c", false),
            ("粘贴", "paste:", "v", false), ("全选", "selectAll:", "a", false)
        ] {
            let item = NSMenuItem(title:title,action:NSSelectorFromString(action),keyEquivalent:shift ? key.uppercased() : key)
            item.keyEquivalentModifierMask = shift ? [.command,.shift] : [.command]
            if action == "editUndo:" || action == "editRedo:" { item.target = self }
            edit.addItem(item)
        }
        let save = NSMenuItem(title:"保存小记",action:#selector(saveNote(_:)),keyEquivalent:"s")
        save.target = self; edit.addItem(save)
        let findNoteItem = NSMenuItem(title:"搜索小记",action:#selector(findNote(_:)),keyEquivalent:"f")
        findNoteItem.target = self; edit.addItem(findNoteItem)
        let addNoteItem = NSMenuItem(title:"追加小记",action:#selector(addNote(_:)),keyEquivalent:"n")
        addNoteItem.target = self; edit.addItem(addNoteItem)
        root.submenu = edit; menu.addItem(root); NSApp.mainMenu = menu
    }
    func installKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self else { return event }
            if let text = event.window?.firstResponder as? GrowingNoteTextView, text.handleMarkdownKey(event) { return nil }
            guard self.panel.isVisible, event.window === self.panel else { return event }
            if let responder = self.panel.firstResponder, responder is NSTextView { return event }
            if event.keyCode == 53 {
                if self.state.settingsPresented { self.state.settingsPresented = false } else { self.hidePanel() }
                return nil
            }
            if self.state.settingsPresented { return event }
            switch event.keyCode {
            case 123: self.state.shift(-1); return nil
            case 124: self.state.shift(1); return nil
            case 53: self.hidePanel(); return nil
            default: if event.charactersIgnoringModifiers?.lowercased() == "t", event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { self.state.today(); return nil }
            }
            return event
        }
    }
    func registerHotkey() {
        var spec = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.togglePopover() }
            return noErr
        }, 1, &spec, context, &eventHandler)
        let identifier = EventHotKeyID(signature:0x5043414C,id:1)
        let status = RegisterEventHotKey(UInt32(kVK_Space),UInt32(controlKey | optionKey),identifier,GetApplicationEventTarget(),0,&hotKey)
        if status != noErr { state.message("快捷键已被占用，可点击菜单栏打开") }
    }
    func applicationWillTerminate(_ notification:Notification) {
        state.onNoteSave?()
        timer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        stateSubscription?.cancel()
    }
}

#if !CALENDAR_CHECKS
@main struct PerpetualCalendarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

#endif
