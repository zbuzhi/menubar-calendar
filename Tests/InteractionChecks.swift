import AppKit
import SwiftUI
import PDFKit
import CalendarCore

@MainActor final class NoteProbeMode: ObservableObject { @Published var editing = false }
struct NoteRowProbe: View {
    @ObservedObject var mode: NoteProbeMode
    let entry: NoteEntry
    var body: some View {
        NoteRow(entry:entry,tags:[],undo:UndoManager(),isEditing:mode.editing,isCollapsed:false,batchMode:false,isSelected:false,allDates:false,
                edit:{ _ in },startEditing:{},endEditing:{},toggleCollapsed:{},toggleSelected:{},delete:{})
            .frame(width:360).fixedSize(horizontal:false,vertical:true)
    }
}

/// Uses an isolated .app domain; never sends mouse/keyboard events to other apps.
@main struct InteractionChecks {
    @MainActor static func main() throws {
        if CommandLine.arguments.contains("--verify-autosave") {
            let stored = AppState().noteDocument.entries.first?.text ?? ""
            precondition(stored.contains("保留的小记，追加"))
            print("PASS: autosaved text is readable in a separate process")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        // Keep checks outside a main-queue callback so nested AppKit loops can run autosave tasks.
        try runChecks(app)
        checkNoteDisclosure()
        try checkRefraction()
    }
    @MainActor static func checkRefraction() throws {
        let panel = CalendarPanel(contentRect:NSRect(x:40,y:40,width:360,height:80),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView:Text("REFRACTION 0123456789 ABCDEF\n真正的文字镜片折射放大").font(.system(size:20)).foregroundStyle(.black)
            .frame(width:360,height:80,alignment:.topLeading).background(.white).overlay { NoteRefraction(active:true,revision:"fixture") })
        panel.contentView = host; panel.orderFrontRegardless()
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        func lenses(_ view: NSView) -> [NoteRefraction.Lens] { (view as? NoteRefraction.Lens).map { [$0] } ?? view.subviews.flatMap { lenses($0) } }
        let lens = lenses(host).first!
        func bitmap() -> NSBitmapImageRep {
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds)!
            host.cacheDisplay(in:host.bounds,to:bitmap); return bitmap
        }
        let before = bitmap()
        func move(_ x: CGFloat) {
            let point = lens.convert(NSPoint(x:x,y:12),to:nil)
            lens.mouseMoved(with:NSEvent.mouseEvent(with:.mouseMoved,location:point,modifierFlags:[],timestamp:1,windowNumber:panel.windowNumber,context:nil,eventNumber:1,clickCount:0,pressure:0)!)
            RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        }
        move(80)
        let after = bitmap(), scale = CGFloat(before.pixelsWide) / 360
        var changed = 0, changedOutside = 0
        for y in 0..<before.pixelsHigh { for x in 0..<before.pixelsWide {
            let a = before.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!, b = after.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
            let delta = abs(a.redComponent-b.redComponent) + abs(a.greenComponent-b.greenComponent) + abs(a.blueComponent-b.blueComponent)
            if delta > 0.12 { changed += 1; if CGFloat(x) > 180 * scale { changedOutside += 1 } }
        } }
        precondition(changed > 30 && changedOutside < 5)
        move(90); precondition(lens.snapshotCount == 1)
        if let path = ProcessInfo.processInfo.environment["CALENDAR_NOTE_TEST_OUTPUT"] {
            let directory = URL(fileURLWithPath:path,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try before.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("refraction-before.png"))
            try after.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("refraction-after.png"))
        }
        print("PASS: rendered glyphs refract locally (\(changed) changed pixels), outer text stays fixed, one cached texture; GPU render \(String(format:"%.2f",lens.renderMilliseconds)) ms")
        panel.orderOut(nil); panel.contentView = nil
    }
    @MainActor static func checkNoteDisclosure() {
        let suite = "org.calendar.note-disclosure." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let state = AppState(defaults:defaults)
        var document = NoteDocument(); document.entries = [NoteEntry(date:"2026-10-24",text:"不应被导航挤动的正文")]
        precondition(state.saveNotes(document))
        let notesPanel = CalendarPanel(contentRect:NSRect(x:40,y:40,width:470,height:570),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        notesPanel.isReleasedWhenClosed = false
        let collapsedHost = NoteHostingView(rootView:NoteEditor(date:state.engine.date(2026,10,24),fitsWindow:true).environmentObject(state))
        notesPanel.contentView = collapsedHost; notesPanel.orderFrontRegardless()
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        func noteStrips(_ view: NSView) -> [NoteTabStrip.StripView] {
            (view as? NoteTabStrip.StripView).map { [$0] } ?? view.subviews.flatMap { noteStrips($0) }
        }
        precondition(noteStrips(collapsedHost).isEmpty)
        func rows(_ view: NSView) -> [NoteRowSettings.Area] { (view as? NoteRowSettings.Area).map { [$0] } ?? view.subviews.flatMap { rows($0) } }
        let collapsedRowY = rows(collapsedHost).first!.convert(.zero,to:nil).y
        document.tags += (0..<50).map { NoteTag(name:"类别\($0)") }
        precondition(state.saveNotes(document))
        let expandedNote = NoteHostingView(rootView:NoteEditor(date:state.engine.date(2026,10,24),fitsWindow:true,initiallyExpandedTags:true).environmentObject(state).transaction { $0.animation = nil; $0.disablesAnimations = true })
        expandedNote.sizingOptions = []; notesPanel.contentView = expandedNote
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        let expandedStrip = noteStrips(expandedNote).first!
        precondition(expandedStrip.bounds.height > expandedStrip.enclosingScrollView!.contentSize.height)
        precondition(expandedStrip.enclosingScrollView!.bounds.height <= 260)
        precondition(abs(rows(expandedNote).first!.convert(.zero,to:nil).y - collapsedRowY) < 1)
        let many = (0..<14).map { NoteTag(name:"分类\($0)") }
        let frames = NoteTabStrip.frames(tags:many,selected:nil,width:280,wraps:true)
        precondition(frames.allSatisfy { $0.maxX <= 280 } && frames.last!.minY > frames.first!.minY)
        precondition(!rows(expandedNote).first!.configuration!.canCollapse)
        expandedStrip.configuration!.select(state.noteDocument.tags.first!.id)
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        if let remaining = noteStrips(expandedNote).first {
            FileHandle.standardError.write(Data("Tag transition: visible=\(!remaining.isHiddenOrHasHiddenAncestor), frame=\(remaining.convert(remaining.bounds,to:expandedNote)), selected=\(String(describing:remaining.configuration?.selected))\n".utf8))
        }
        precondition(noteStrips(expandedNote).isEmpty)
        print("PASS: floating tags keep row geometry fixed, wrap within reserved width, select and collapse; single-line notes cannot fold")
        notesPanel.orderOut(nil); notesPanel.contentView = nil
    }
    @MainActor static func runChecks(_ app: NSApplication) throws {
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
        precondition(restored.noteDocument.entries(date:"2026-10-24").first?.text == "保留的小记")
        print("PASS: old settings, favorites and notes survive new preference options")

        precondition(defaults.dictionary(forKey:"notes.v1")?["2026-10-24"] as? String == "保留的小记")
        let legacyID = restored.noteDocument.entries[0].id
        precondition(AppState().noteDocument.entries[0].id == legacyID)
        let tag = restored.noteDocument.tags[0]
        var document = restored.noteDocument
        document.entries.append(NoteEntry(date:"2026-10-25",text:"跨日工作",tagIDs:[tag.id],isCompleted:true))
        precondition(restored.saveNotes(document))
        let reloaded = AppState()
        precondition(reloaded.noteDocument.entries.count == 2)
        precondition(reloaded.noteDocument.entries(date:"2026-10-24").count == 1)
        precondition(reloaded.noteDocument.entries(tagID:tag.id).first?.isCompleted == true)
        precondition(reloaded.noteDocument.entries[0].id == legacyID)
        print("PASS: migration retains v1, stable IDs and structured notes survive restart")

        let draft = NoteDraft()
        draft.document = document
        draft.undo.groupsByEvent = false
        draft.undo.beginUndoGrouping()
        draft.change { $0.entries.removeAll { $0.date == "2026-10-24" } }
        draft.undo.endUndoGrouping()
        precondition(draft.document.entries.count == 1)
        draft.undo.undo()
        precondition(draft.document == document)
        draft.undo.redo()
        precondition(draft.document.entries.count == 1)
        print("PASS: whole-document undo and redo retain other dates")

        var future = document
        future.schemaVersion = 99
        let futureData = try future.encoded()
        defaults.set(futureData,forKey:"notes.v3")
        let protected = AppState()
        precondition(protected.notesReadOnly && !protected.saveNotes(NoteDocument()))
        precondition(defaults.data(forKey:"notes.v3") == futureData)
        defaults.set(try document.encoded(),forKey:"notes.v3")
        var savedByKeyboard = false
        state.onNoteSave = { savedByKeyboard = true }
        let saveKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                                      windowNumber:0,context:nil,characters:"s",charactersIgnoringModifiers:"s",
                                      isARepeat:false,keyCode:1)!
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:saveKey) && savedByKeyboard)
        state.onNoteSave = nil
        state.noteUndoManager = draft.undo
        let undoKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                                      windowNumber:0,context:nil,characters:"z",charactersIgnoringModifiers:"z",
                                      isARepeat:false,keyCode:6)!
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:undoKey))
        precondition(draft.document == document)
        state.noteUndoManager = nil
        print("PASS: future versions remain untouched; native editing shortcuts installed")

        // Exercise native text selection and undo through our own isolated editor window.
        let editorWindow = CalendarPanel(contentRect:NSRect(x:0,y:0,width:476,height:600),
                                    styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
        editorWindow.isReleasedWhenClosed = false
        editorWindow.contentView = NSHostingView(rootView:NoteEditor(date:state.engine.date(2026,10,24),initialEditingID:state.noteDocument.entries.first?.id).environmentObject(state))
        NSApp.activate(ignoringOtherApps:true)
        editorWindow.makeKeyAndOrderFront(nil)
        editorWindow.contentView!.layoutSubtreeIfNeeded()
        // Unlike app.run(), the standalone check main does not pump AppKit activation events.
        let activationDeadline = Date().addingTimeInterval(0.3)
        repeat {
            if let event = app.nextEvent(matching:.any,until:activationDeadline,inMode:.default,dequeue:true) {
                app.sendEvent(event)
            }
        } while Date() < activationDeadline
        editorWindow.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        func textViews(_ view: NSView) -> [NSTextView] {
            (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
        }
        guard let text = textViews(editorWindow.contentView!).first(where:{ $0.string == "保留的小记" }) else {
            fatalError("Missing native note text editor")
        }
        if NSApp.keyWindow !== editorWindow {
            editorWindow.makeKey()
            RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        }
        if NSApp.keyWindow !== editorWindow {
            NSRunningApplication.current.activate(options:[.activateAllWindows,.activateIgnoringOtherApps])
            let focusDeadline = Date().addingTimeInterval(1)
            repeat {
                editorWindow.makeKeyAndOrderFront(nil)
                if let event = app.nextEvent(matching:.any,until:Date().addingTimeInterval(0.05),inMode:.default,dequeue:true) { app.sendEvent(event) }
            } while NSApp.keyWindow !== editorWindow && Date() < focusDeadline
        }
        precondition(NSApp.keyWindow === editorWindow)
        precondition(editorWindow.makeFirstResponder(text))
        text.insertText("，追加",replacementRange:NSRange(location:text.string.utf16.count,length:0))
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        precondition(text.string == "保留的小记，追加")
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:undoKey))
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        precondition(text.string == "保留的小记")
        let selectKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                                        windowNumber:editorWindow.windowNumber,context:nil,characters:"a",
                                        charactersIgnoringModifiers:"a",isARepeat:false,keyCode:0)!
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:selectKey))
        precondition(text.selectedRange().length == text.string.utf16.count)
        let redoKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.shift],timestamp:0,
                                      windowNumber:editorWindow.windowNumber,context:nil,characters:"Z",
                                      charactersIgnoringModifiers:"Z",isARepeat:false,keyCode:6)!
        precondition(state.noteUndoManager?.canRedo == true)
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:redoKey))
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        precondition(text.string == "保留的小记，追加")
        RunLoop.main.run(until:Date().addingTimeInterval(0.55))
        precondition(state.noteDocument.entries(date:"2026-10-24").first?.text == "保留的小记，追加")
        precondition(AppState().noteDocument.entries(date:"2026-10-24").first?.text == "保留的小记，追加")
        let reload = Process(); reload.executableURL = Bundle.main.executableURL
        reload.arguments = ["--verify-autosave"]
        try reload.run(); reload.waitUntilExit(); precondition(reload.terminationStatus == 0)
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:saveKey))
        precondition(editorWindow.isVisible)
        precondition(text.string == "保留的小记，追加")
        precondition(text.enclosingScrollView?.documentView !== text)
        precondition(!text.isHorizontallyResizable)

        let beforeFormatting = text.string
        func markdownKey(_ key: String,_ code: UInt16 = 0) {
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                                        windowNumber:editorWindow.windowNumber,context:nil,characters:key,
                                        charactersIgnoringModifiers:key,isARepeat:false,keyCode:code)!
            precondition(text.performKeyEquivalent(with:event))
        }
        text.setSelectedRange((text.string as NSString).range(of:"保留"))
        markdownKey("b"); precondition(text.string.hasPrefix("**保留**"))
        markdownKey("u"); precondition(text.string.hasPrefix("**<u>保留</u>**"))
        let formatted = NoteMarkdown.inline(text.string)
        precondition(String(formatted.characters) == beforeFormatting)
        precondition(formatted.runs.contains { $0.underlineStyle != nil && $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        let pdfInline = NoteMarkdown.attributedInline(text.string,font:.systemFont(ofSize:12))
        precondition((pdfInline.attribute(.underlineStyle,at:0,effectiveRange:nil) as? Int) == NSUnderlineStyle.single.rawValue)
        markdownKey("u"); markdownKey("b"); precondition(text.string == beforeFormatting)
        for key in ["i","e"] {
            text.setSelectedRange((text.string as NSString).range(of:"保留"))
            markdownKey(key); markdownKey(key); precondition(text.string == beforeFormatting)
        }
        text.setSelectedRange(NSRange(location:0,length:0))
        markdownKey("1"); precondition(text.string == "# " + beforeFormatting)
        markdownKey("2"); precondition(text.string == "## " + beforeFormatting)
        markdownKey("2"); precondition(text.string == beforeFormatting)
        precondition(String(NoteMarkdown.inline("`<u>literal</u>`").characters) == "<u>literal</u>")
        print("PASS: native heading/bold/italic/underline/code shortcuts, toggles and PDF underline")

        let longEdit = "\n" + (1...22).map { "\($0). 不裁切的长正文，继续书写并完整显示。" }.joined(separator:"\n")
        text.insertText(longEdit,replacementRange:NSRange(location:text.string.utf16.count,length:0))
        RunLoop.main.run(until:Date().addingTimeInterval(0.12))
        precondition(text.bounds.height > 350)
        precondition(text.string.hasSuffix("22. 不裁切的长正文，继续书写并完整显示。"))
        editorWindow.makeKeyAndOrderFront(nil)
        precondition(editorWindow.makeFirstResponder(text))
        let composition = "\n输入法完成"
        text.setMarkedText(composition,selectedRange:NSRange(location:composition.utf16.count,length:0),
                           replacementRange:NSRange(location:text.string.utf16.count,length:0))
        precondition(text.hasMarkedText())
        let outside = NSPoint(x:24,y:editorWindow.contentView!.bounds.height - 48)
        let clickDown = NSEvent.mouseEvent(with:.leftMouseDown,location:outside,modifierFlags:[],timestamp:0,
                                          windowNumber:editorWindow.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let clickUp = NSEvent.mouseEvent(with:.leftMouseUp,location:outside,modifierFlags:[],timestamp:0.01,
                                        windowNumber:editorWindow.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:0)!
        app.postEvent(clickDown,atStart:false); app.postEvent(clickUp,atStart:false)
        let clickDeadline = Date().addingTimeInterval(0.1)
        repeat {
            if let event = app.nextEvent(matching:.any,until:clickDeadline,inMode:.default,dequeue:true) { app.sendEvent(event) }
        } while Date() < clickDeadline
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        precondition(!textViews(editorWindow.contentView!).contains(where:{ $0 === text }))
        precondition(state.noteDocument.entries.first!.text.hasSuffix("输入法完成"))
        let countBeforeAdd = state.noteDocument.entries.count
        let addKey = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                                     windowNumber:editorWindow.windowNumber,context:nil,characters:"n",
                                     charactersIgnoringModifiers:"n",isARepeat:false,keyCode:45)!
        precondition(NSApp.mainMenu!.performKeyEquivalent(with:addKey))
        RunLoop.main.run(until:Date().addingTimeInterval(0.4))
        precondition(textViews(editorWindow.contentView!).contains(where:{ $0.string.isEmpty && !$0.isFieldEditor }))
        editorWindow.close(); editorWindow.contentView = nil
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        precondition(AppState().noteDocument.entries(date:"2026-10-24").first?.text.hasSuffix("输入法完成") == true)
        precondition(AppState().noteDocument.entries.count == countBeforeAdd)
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        print("PASS: native typing, IME commit, click-away editing, autosave and Command-S without dismissal")

        var clean = NoteDocument()
        let blank = NoteEntry(date:"2026-10-24")
        let taggedBlank = NoteEntry(date:"2026-10-24",tagIDs:[clean.tags[0].id])
        clean.entries = [blank,taggedBlank]
        precondition(clean.cleaned().entries.map(\.id) == [taggedBlank.id])
        let untimedA = NoteEntry(date:"2026-10-24",text:"先追加"), untimedB = NoteEntry(date:"2026-10-24",text:"后追加")
        let late = NoteEntry(date:"2026-10-24",text:"晚上",dueMinutes:1080), early = NoteEntry(date:"2026-10-24",text:"上午",dueMinutes:540)
        clean.entries = [untimedA,late,untimedB,early]
        precondition(clean.displayEntries().map(\.id) == [early.id,late.id,untimedA.id,untimedB.id])
        precondition(!NoteSwipe.shouldConfirmDelete(-75) && NoteSwipe.shouldConfirmDelete(-76))
        var selectedColor: String?
        let colorControl = NoteTagContextMenu(tag:clean.tags[0],rename:{},remove:{},setColor:{ selectedColor = $0 })
        let colorCoordinator = colorControl.makeCoordinator()
        let nativeMenu = colorCoordinator.menu()
        let colorMenu = nativeMenu.items[1].submenu!
        precondition(colorMenu.items.allSatisfy { $0.image != nil && !$0.image!.isTemplate })
        let swatch = NSBitmapImageRep(data:colorMenu.items[0].image!.tiffRepresentation!)!
        let pixel = swatch.colorAt(x:7,y:7)!.usingColorSpace(.deviceRGB)!
        precondition(pixel.blueComponent > pixel.redComponent)
        colorMenu.performActionForItem(at:1)
        precondition(selectedColor == "green")
        print("PASS: empty-draft cleanup, stable deadline ordering, swipe threshold and real-color native menu")

        let tabWindow = CalendarPanel(contentRect:NSRect(x:0,y:0,width:420,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        tabWindow.isReleasedWhenClosed = false
        let strip = NoteTabStrip.StripView(frame:NSRect(x:0,y:0,width:420,height:32))
        var orderedTabs = NoteDocument()
        let movingID = orderedTabs.tags[0].id
        strip.configure(NoteTabStrip(tags:orderedTabs.tags,selected:nil,accent:.systemBlue,mode:"jelly",select:{ _ in },move:{ source,target in orderedTabs.moveTag(source,over:target) },context:{ _ in NSMenu() }),viewport:420)
        tabWindow.contentView = strip; tabWindow.orderFrontRegardless()
        let tabViews = strip.subviews.compactMap { $0 as? NoteTabStrip.StripView.TabView }
        let sourceTab = tabViews.first { $0.id == movingID }!, targetTab = tabViews.filter { $0.id != nil }.max { $0.frame.midX < $1.frame.midX }!
        func tabEvent(_ type: NSEvent.EventType,_ point: NSPoint,_ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:time,windowNumber:tabWindow.windowNumber,
                               context:nil,eventNumber:10,clickCount:1,pressure:1)!
        }
        let sourcePoint = strip.convert(NSPoint(x:sourceTab.frame.midX,y:16),to:nil)
        let targetPoint = strip.convert(NSPoint(x:targetTab.frame.midX,y:16),to:nil)
        // Clear synthetic click-away events left by the previous isolated editor check.
        while app.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:.distantPast,inMode:.default,dequeue:true) != nil {}
        app.postEvent(tabEvent(.leftMouseDragged,targetPoint,1.4),atStart:false)
        app.postEvent(tabEvent(.leftMouseUp,targetPoint,1.5),atStart:false)
        sourceTab.mouseDown(with:tabEvent(.leftMouseDown,sourcePoint,1))
        precondition(orderedTabs.tags.last?.id == movingID)
        tabWindow.close()
        let probeWindow = CalendarPanel(contentRect:NSRect(x:0,y:0,width:380,height:180),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        probeWindow.isReleasedWhenClosed = false
        let mode = NoteProbeMode()
        let probe = NSHostingView(rootView:NoteRowProbe(mode:mode,entry:NoteEntry(date:"2026-10-24",text:"普通小记首行\n第二行保持相同高度")).environmentObject(state))
        probeWindow.contentView = probe; probeWindow.orderFrontRegardless()
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        let readingSize = probe.fittingSize
        mode.editing = true
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let editingSize = probe.fittingSize
        if abs(readingSize.height - editingSize.height) > 1 { FileHandle.standardError.write(Data("Row focus size: read=\(readingSize), edit=\(editingSize)\n".utf8)) }
        precondition(abs(readingSize.height - editingSize.height) <= 1)
        let fullWidth = textViews(probe).first { !$0.isFieldEditor }!.bounds.width
        state.noteSimpleDisplay = true
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        precondition(AppState().noteSimpleDisplay)
        precondition(textViews(probe).first { !$0.isFieldEditor }!.bounds.width > fullWidth + 20)
        state.noteSimpleDisplay = false
        let hover = HoverTrackingView(frame:NSRect(x:0,y:0,width:360,height:160))
        probe.addSubview(hover)
        hover.configure(frames:[CGRect(x:0,y:0,width:360,height:100),CGRect(x:0,y:112,width:360,height:24)],color:.systemBlue,mode:"off")
        let hoverPoint = hover.convert(NSPoint(x:100,y:95),to:nil)
        let hoverEvent = NSEvent.mouseEvent(with:.mouseMoved,location:hoverPoint,modifierFlags:[],timestamp:1,windowNumber:probeWindow.windowNumber,context:nil,eventNumber:1,clickCount:0,pressure:0)!
        hover.mouseMoved(with:hoverEvent)
        precondition(hover.subviews.first!.alphaValue == 1 && abs(hover.subviews.first!.frame.height - 98) < 1)
        hover.configure(frames:[CGRect(x:0,y:0,width:360,height:100)],color:.systemBlue,mode:"off",rowStyle:true)
        hover.mouseMoved(with:hoverEvent)
        precondition(hover.subviews.first!.frame == CGRect(x:0,y:0,width:360,height:100))
        hover.removeFromSuperview()
        probeWindow.close(); probeWindow.contentView = nil
        let pale = NoteProgressTint.rgb(0), orange = NoteProgressTint.rgb(0.65), red = NoteProgressTint.rgb(1)
        precondition(orange.red > orange.blue && red.red > red.green * 2 && pale.blue > pale.red)
        print("PASS: native long-press reorder, focus geometry, saved simple mode with wider text, variable-height glass hover and deadline colors")

        delegate.showPopover()
        state.noteEditorDate = state.engine.date(2026,10,24)
        RunLoop.main.run(until:Date().addingTimeInterval(0.1))
        let notesPanel = delegate.noteWindow!.panel
        precondition(notesPanel.isVisible && notesPanel.styleMask.contains(.resizable))
        precondition(delegate.noteWindow!.anchorPanel?.isVisible == true)
        state.toggleNoteEditor(state.engine.date(2026,10,24)); precondition(!notesPanel.isVisible)
        state.toggleNoteEditor(state.engine.date(2026,10,24)); precondition(notesPanel.isVisible)
        if let path = ProcessInfo.processInfo.environment["CALENDAR_NOTE_TEST_OUTPUT"], let view = notesPanel.contentView {
            let directory = URL(fileURLWithPath:path,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("notes-native-window.png"))
            }
        }
        let savePanel = NSSavePanel()
        NoteSaveDialog.prepare(savePanel,near:notesPanel)
        precondition(savePanel.level.rawValue > notesPanel.level.rawValue)
        let visibleScreen = notesPanel.screen!.visibleFrame
        precondition(abs(savePanel.frame.midX - visibleScreen.midX) < 2)
        precondition(abs(savePanel.frame.midY - visibleScreen.midY) < 2)
        var wrappingDocument = state.noteDocument
        wrappingDocument.entries[0].text = String(repeating:"窗口缩放时，正文应该按照当前宽度实时重新换行。",count:24)
        precondition(state.saveNotes(wrappingDocument))
        let adaptive = NoteHostingView(rootView:NoteEditor(date:state.engine.date(2026,10,24),initialEditingID:state.noteDocument.entries.first?.id,fitsWindow:true).environmentObject(state))
        adaptive.sizingOptions = []; notesPanel.contentView = adaptive
        notesPanel.setContentSize(NSSize(width:380,height:650))
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let narrowEditor = textViews(adaptive).first { !$0.isFieldEditor }!
        let narrowHeight = narrowEditor.bounds.height
        let narrowWidth = narrowEditor.bounds.width
        notesPanel.setContentSize(NSSize(width:620,height:650))
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        let wideEditor = textViews(adaptive).first { !$0.isFieldEditor }!
        precondition(wideEditor.bounds.width > narrowWidth)
        if wideEditor.bounds.height >= narrowHeight {
            FileHandle.standardError.write(Data("Resize layout: narrow=\(narrowWidth)x\(narrowHeight), wide=\(wideEditor.bounds.size), host=\(adaptive.bounds.size)\n".utf8))
        }
        precondition(wideEditor.bounds.height < narrowHeight)
        precondition(abs(AppState().noteEditorSize.width - 620) < 1)
        precondition(abs(AppState().noteEditorSize.height - 650) < 1)
        state.notePinned = true
        precondition(!delegate.panel.isVisible && notesPanel.isVisible && delegate.noteWindow!.anchorPanel?.isVisible == false)
        delegate.showPopover()
        precondition(delegate.noteWindow!.anchorPanel?.isVisible == true)
        let pinnedOrigin = notesPanel.frame.origin
        notesPanel.setFrameOrigin(NSPoint(x:pinnedOrigin.x + 10,y:pinnedOrigin.y - 8))
        RunLoop.main.run(until:Date().addingTimeInterval(0.05))
        precondition(AppState().notePinned && AppState().noteWindowOrigin == notesPanel.frame.origin)
        delegate.hidePanel()
        precondition(!delegate.panel.isVisible && notesPanel.isVisible && state.noteEditorDate != nil)
        precondition(notesPanel.frame.origin == state.noteWindowOrigin)
        state.onNoteResetSize?()
        precondition(state.noteEditorSize == AppState.defaultNoteEditorSize)
        state.onNoteClose?()
        precondition(!notesPanel.isVisible)
        state.notePinned = false
        print("PASS: adaptive live layout, saved size/position, independent pinning and explicit close")

        let storageSuite = "org.menubar-calendar.notes-migration.\(UUID())"
        let migrationDefaults = UserDefaults(suiteName:storageSuite)!
        defer { migrationDefaults.removePersistentDomain(forName:storageSuite) }
        var v2Object = try JSONSerialization.jsonObject(with:document.encoded()) as! [String:Any]
        v2Object["schemaVersion"] = 2
        v2Object["tags"] = (v2Object["tags"] as! [[String:Any]]).map { row in var copy = row; copy.removeValue(forKey:"color"); return copy }
        let v2Data = try JSONSerialization.data(withJSONObject:v2Object)
        migrationDefaults.set(v2Data,forKey:"notes.v2")
        let migrated = AppState(defaults:migrationDefaults)
        precondition(!migrated.notesReadOnly && migrated.noteDocument.schemaVersion == 3)
        precondition(migrated.noteDocument.entries.map(\.id) == document.entries.map(\.id))
        precondition(migrationDefaults.data(forKey:"notes.v2") == v2Data)
        precondition(migrationDefaults.data(forKey:"notes.v3") != nil)
        var categories = migrated.noteDocument
        let first = categories.tags[0].id, second = categories.tags[1].id
        categories.entries[0].tagIDs = [first]
        categories.removeTag(first,transferringTo:second)
        precondition(categories.entries[0].tagIDs == [second] && categories.entries[0].text == document.entries[0].text)
        categories.removeTag(second)
        precondition(categories.entries[0].tagIDs.isEmpty && categories.entries.count == document.entries.count)
        var ordered = NoteDocument()
        let moved = ordered.tags.last!.id, target = ordered.tags.first!.id
        ordered.moveTag(moved,over:target)
        precondition(ordered.tags.first?.id == moved)
        ordered.moveTag(moved,over:ordered.tags.last!.id)
        precondition(ordered.tags.last?.id == moved)
        let e = state.engine
        let timed = NoteEntry(date:"2026-10-24",text:"进度",dueMinutes:18 * 60,now:e.date(2026,10,24,hour:9))
        let halfway = NoteDocument.timeProgress(for:timed,now:e.date(2026,10,24,hour:13,minute:30),engine:e)!
        precondition(abs(halfway - 0.5) < 0.001)
        precondition(NoteDocument.timeProgress(for:timed,now:e.date(2026,10,25),engine:e) == nil)
        precondition(NoteDocument.timeProgress(for:timed,now:e.date(2026,10,24,hour:20),engine:e) == 1)
        let previousDayStart = NoteEntry(date:"2026-10-24",text:"提前添加",dueMinutes:18 * 60,now:e.date(2026,10,23,hour:12))
        precondition(abs(NoteDocument.timeProgress(for:previousDayStart,now:e.date(2026,10,24,hour:9),engine:e)! - 0.7) < 0.001)
        var ranged = NoteDocument()
        let work = ranged.tags[0].id, life = ranged.tags[1].id
        let both = NoteEntry(date:"2026-10-24",text:"同时属于两个标签",tagIDs:[work,life])
        let free = NoteEntry(date:"2026-10-25",text:"未归类")
        ranged.entries = [NoteEntry(date:"2026-10-23",text:"范围之前",tagIDs:[work]),both,free,
                          NoteEntry(date:"2026-10-26",text:"范围之后",tagIDs:[life])]
        precondition(ranged.exportEntries(from:"2026-10-24",through:"2026-10-25",tagIDs:[work,life],includeUntagged:true).map(\.id) == [both.id,free.id])
        precondition(ranged.exportEntries(from:"2026-10-24",through:"2026-10-25",tagIDs:[work,life],includeUntagged:false).map(\.id) == [both.id])
        precondition(ranged.exportEntries(tagIDs:[],includeUntagged:true).map(\.id) == [free.id])
        print("PASS: progress uses actual addition time; inclusive date range, multi-tag union and deduplication")
        let cleanDraft = NoteDraft(); cleanDraft.begin(migrated)
        var newer = migrated.noteDocument
        newer.entries.append(NoteEntry(date:"2026-10-24",text:"其他入口的新内容"))
        precondition(migrated.saveNotes(newer))
        cleanDraft.flush()
        precondition(migrated.noteDocument.entries.last?.text == "其他入口的新内容")
        print("PASS: v2 migration backup, tag transfer/removal/reordering, progress and clean-session safety")

        var exported = NoteDocument()
        let longBody = (1...85).map { "\($0). 长文本完整显示与分页验证，**重点内容**、普通文字和换行。" }.joined(separator:"\n")
        exported.entries = [NoteEntry(date:"2026-10-24",text:"# 今天的计划\n\n- 整理需求\n- **确认进度**\n\n> 保持界面简单\n\n" + longBody + "\n\n最后一条正文-END",tagIDs:[exported.tags[0].id,exported.tags[1].id],dueMinutes:1110)]
        let md = NoteExport.markdown(exported,title:"小记导出验证")
        precondition(md.components(separatedBy:"最后一条正文-END").count == 2)
        precondition(md.contains("预计 18:30") && md.contains("**确认进度**"))
        let pdfData = try NoteExport.pdf(exported,title:"小记导出验证")
        let pdf = PDFDocument(data:pdfData)!
        precondition(pdf.pageCount > 1)
        precondition(pdf.string!.contains("最后一条正文-END"))
        if let path = ProcessInfo.processInfo.environment["CALENDAR_NOTE_TEST_OUTPUT"] {
            let directory = URL(fileURLWithPath:path,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try pdfData.write(to:directory.appendingPathComponent("notes-export.pdf"))
            try md.write(to:directory.appendingPathComponent("notes-export.md"),atomically:true,encoding:.utf8)
            for index in [0,pdf.pageCount - 1] {
                let pageImage = pdf.page(at:index)!.thumbnail(of:NSSize(width:595,height:842),for:.mediaBox)
                let png = NSBitmapImageRep(data:pageImage.tiffRepresentation!)!.representation(using:.png,properties:[:])!
                try png.write(to:directory.appendingPathComponent("notes-export-page-\(index + 1).png"))
            }
        }
        print("PASS: text-only Markdown and native multipage PDF export without duplicate records")

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
