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
        state.softwareUpdater.beforeManualCheck = { [weak self] in self?.hidePanel() }
        state.softwareUpdater.start()
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        statusItem.button?.toolTip = "日历 · ⌃⌥空格打开 · 右键复制"
        panel = CalendarPanel(contentRect:NSRect(x:0,y:0,width:420,height:700),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title = "日历"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace,.fullScreenAuxiliary]
        panel.contentView = TransparentHostingView(rootView:WorkspaceView().environmentObject(state))
        state.onSettings = { [weak self] in self?.toggleSettings() }
        state.onPreferencesChange = { [weak self] in self?.updateStatus() }
        stateSubscription = state.objectWillChange.sink { [weak self] _ in self?.scheduleLayout() }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.pinned else { return }
                self.hidePanel()
            }
        }
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        if let timer { RunLoop.main.add(timer,forMode:.common) }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        dateObserver = NotificationCenter.default.addObserver(forName:.NSCalendarDayChanged,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus() } }
        installKeyboard()
        registerHotkey()
        if ProcessInfo.processInfo.arguments.contains("--show") { DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { self.showPopover() } }
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
    }
    func updateStatus() {
        let now = Date()
        let value = state.render(state.preferences.menuTemplate,at:now)
        statusItem.button?.title = value.isEmpty ? "日历" : value
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize:12,weight:.regular)
        statusItem.button?.setAccessibilityLabel("日历，"+value)
        let today = state.engine.key(now)
        if let lastSelectionDay, lastSelectionDay != today, state.engine.key(state.selected) == lastSelectionDay { state.today() }
        lastSelectionDay = today
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
    }
    func hidePanel() { panel.orderOut(nil); state.settingsPresented = false; state.noteEditorDate = nil }
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
        add(menu,"退出日历",#selector(quit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    func add(_ menu:NSMenu,_ title:String,_ selector:Selector) { let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item) }
    @objc func openCalendar() { showPopover() }
    @objc func openSettings() { showSettings() }
    @objc func checkSoftwareUpdates() { state.softwareUpdater.check() }
    @objc func copyCurrent() { state.copy(state.preferences.menuTemplate) }
    @objc func copyStandard() { state.copy(state.preferences.copyTemplate) }
    @objc func quit() { NSApp.terminate(nil) }
    func installKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else { return event }
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
        timer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        stateSubscription?.cancel()
    }
}

@main struct PerpetualCalendarApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
