import AppKit
import CalendarCore

/// Uses an isolated .app domain; never sends mouse/keyboard events to other apps.
@main struct InteractionChecks {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let defaults = UserDefaults.standard
        defer { if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName:domain) } }

        var original = Preferences()
        original.theme = "dark"
        original.zodiac = "text"
        original.clockTemplate = "{HH}:{mm}:{ss}"
        original.favorites = [SavedFormat(name:"自用",template:"{yyyy}年{M}月{d}日")]
        var oldJSON = try JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as! [String:Any]
        for key in ["boldText","glassStyle","glassTint"] { oldJSON.removeValue(forKey:key) }
        defaults.set(try JSONSerialization.data(withJSONObject:oldJSON),forKey:"preferences.v1")
        defaults.set(["2026-10-24":"保留的小记"],forKey:"notes.v1")

        let delegate = AppDelegate()
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
        let state = delegate.state
        precondition(state.preferences.theme == "dark" && state.preferences.zodiac == "text")
        precondition(state.preferences.favorites.first?.name == "自用" && !state.usesBoldText)
        precondition(state.preferences.clock && state.preferences.traditional == "ke")
        precondition(state.preferences.clockTemplate == "{HH}:{mm}:{ss}")
        state.preferences.boldText = true
        state.preferences.glassStyle = "regular"
        state.preferences.glassTint = 0.4
        let restored = AppState()
        precondition(restored.usesBoldText && restored.preferences.glassStyle == "regular")
        precondition(restored.preferences.glassTint == 0.4)
        precondition(restored.notes["2026-10-24"] == "保留的小记")
        print("PASS: old settings, favorites and notes survive new preference options")

        guard let rect = delegate.statusItemFrame else { fatalError("Missing native status item") }
        let menuPoint = NSPoint(x:rect.midX,y:rect.midY)
        delegate.hidePanel()
        for _ in 0..<6 {
            delegate.statusClicked()
            precondition(delegate.panel.isVisible)
            state.settingsPresented = true
            delegate.handleOutsideClick(at:menuPoint)
            precondition(delegate.panel.isVisible && state.settingsPresented)
            delegate.statusClicked()
            precondition(!delegate.panel.isVisible && !state.settingsPresented)
        }
        print("PASS: menu mouse-down does not preempt mouse-up; repeated clicks toggle and close settings")
        delegate.showPopover()
        delegate.handleOutsideClick(at:NSPoint(x:rect.minX - 20,y:rect.minY - 20))
        precondition(!delegate.panel.isVisible)
        delegate.showPopover()
        state.pinned = true
        delegate.handleOutsideClick(at:NSPoint(x:rect.minX - 20,y:rect.minY - 20))
        precondition(delegate.panel.isVisible)
        delegate.statusClicked()
        precondition(!delegate.panel.isVisible)
        print("PASS: outside clicks close unpinned panels; explicit menu click closes pinned panels")

        state.openSettings(tab:"formats",target:"copy")
        precondition(delegate.panel.isVisible && state.settingsPresented)
        precondition(state.settingsTab == "formats" && state.formatTarget == "copy")
        state.openSettings(tab:"updates")
        precondition(delegate.panel.isVisible && state.settingsPresented && state.settingsTab == "updates")
        print("PASS: direct settings destinations preserve the calendar and settings panel")
        delegate.hidePanel()
        delegate.applicationWillTerminate(Notification(name:NSApplication.willTerminateNotification))
        NSStatusBar.system.removeStatusItem(delegate.statusItem)
    }
}
