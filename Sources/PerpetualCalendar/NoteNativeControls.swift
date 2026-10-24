import AppKit
import SwiftUI
import CalendarCore

/// Freeze native menus for the entire tracking session. SwiftUI updates never rebuild a submenu under the pointer.
struct NoteTagContextMenu: NSViewRepresentable {
    let tag: NoteTag
    let rename: () -> Void
    let remove: () -> Void
    let setColor: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let view = MenuArea(); view.buildMenu = { [weak coordinator = context.coordinator] in coordinator?.menu() ?? NSMenu() }; return view
    }
    func updateNSView(_ view: NSView,context: Context) { context.coordinator.parent = self }
    final class MenuArea: NSView {
        var buildMenu: (() -> NSMenu)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard visibleRect.contains(convert(point,from:superview)) else { return nil }
            let event = NSApp.currentEvent
            return event?.type == .rightMouseDown || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true) ? self : nil
        }
        override func rightMouseDown(with event: NSEvent) { NSMenu.popUpContextMenu(buildMenu?() ?? NSMenu(),with:event,for:self) }
        override func mouseDown(with event: NSEvent) { rightMouseDown(with:event) }
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NoteTagContextMenu
        init(_ parent: NoteTagContextMenu) { self.parent = parent }
        func menu() -> NSMenu {
            let menu = NSMenu()
            let rename = NSMenuItem(title:"重命名…",action:#selector(renameTag),keyEquivalent:""); rename.target = self; menu.addItem(rename)
            let root = NSMenuItem(title:"颜色标记",action:nil,keyEquivalent:"")
            let colors = NSMenu()
            for (index,name) in NoteColors.names.enumerated() {
                let item = NSMenuItem(title:NoteColors.titles[index],action:#selector(changeColor(_:)),keyEquivalent:"")
                item.target = self; item.representedObject = name
                item.image = Self.swatch(NoteColors.nativeColor(name))
                item.state = parent.tag.color == name ? .on : .off
                colors.addItem(item)
            }
            root.submenu = colors; menu.addItem(root); menu.addItem(.separator())
            let remove = NSMenuItem(title:"删除标签…",action:#selector(removeTag),keyEquivalent:""); remove.target = self; menu.addItem(remove)
            return menu
        }
        static func swatch(_ color: NSColor) -> NSImage {
            let image = NSImage(size:NSSize(width:14,height:14),flipped:false) { rect in
                color.setFill(); NSBezierPath(ovalIn:rect.insetBy(dx:2,dy:2)).fill(); return true
            }
            image.isTemplate = false
            return image
        }
        @objc func renameTag() { parent.rename() }
        @objc func removeTag() { parent.remove() }
        @objc func changeColor(_ sender: NSMenuItem) { if let name = sender.representedObject as? String { parent.setColor(name) } }
    }
}

/// Ends a native editing session on clicks elsewhere without consuming the click intended for a control.
struct NoteEditingBoundary: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view; context.coordinator.start(); return view
    }
    func updateNSView(_ view: NSView,context: Context) {}
    static func dismantleNSView(_ view: NSView,coordinator: Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseUp,.rightMouseDown]) { [weak self] event in
                guard let viewport = self?.view, let window = viewport.window,
                      let text = window.firstResponder as? GrowingNoteTextView else { return event }
                guard event.window === window else { window.makeFirstResponder(nil); return event }
                var active = text.convert(text.bounds.intersection(text.visibleRect),to:nil).intersection(viewport.convert(viewport.bounds,to:nil))
                var ancestor = text.superview
                while let view = ancestor {
                    active = active.intersection(view.convert(view.bounds,to:nil))
                    ancestor = view.superview
                }
                if !active.contains(event.locationInWindow) { window.makeFirstResponder(nil) }
                return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

struct NoteTrackpadSwipe: NSViewRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view; context.coordinator.start(); return view
    }
    func updateNSView(_ view: NSView,context: Context) { context.coordinator.parent = self }
    static func dismantleNSView(_ view: NSView,coordinator: Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        var parent: NoteTrackpadSwipe
        weak var view: NSView?
        var monitor: Any?
        var displacement: CGFloat = 0
        var tracking = false
        var pending: Task<Void,Never>?
        init(_ parent: NoteTrackpadSwipe) { self.parent = parent }
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
                guard let self, self.parent.enabled, let view = self.view, event.window === view.window,
                      event.momentumPhase.isEmpty else { return event }
                if event.phase.contains(.cancelled) {
                    if self.tracking { self.displacement = 0; self.finish() }
                    return event
                }
                guard view.visibleRect.contains(view.convert(event.locationInWindow,from:nil)) else {
                    if self.tracking && event.phase.contains(.ended) { self.finish() }
                    return event
                }
                if !self.tracking {
                    guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5, abs(event.scrollingDeltaX) > 1 else { return event }
                    self.tracking = true; self.displacement = 0
                }
                self.displacement = min(0,self.displacement + event.scrollingDeltaX)
                self.parent.changed(self.displacement)
                self.pending?.cancel()
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) { self.finish() }
                else if event.phase.isEmpty {
                    self.pending = Task { [weak self] in
                        do { try await Task.sleep(nanoseconds:180_000_000) } catch { return }
                        self?.finish()
                    }
                }
                return nil
            }
        }
        func finish() { guard tracking else { return }; tracking = false; parent.ended(displacement); displacement = 0 }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; pending?.cancel() }
    }
}

/// A small strip above the header remains draggable without intercepting text selection or buttons.
struct NoteWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragArea() }
    func updateNSView(_ view: NSView,context: Context) {}
    final class DragArea: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with:event) }
        override func resetCursorRects() { addCursorRect(bounds,cursor:.openHand) }
    }
}

struct NoteRowSettings: NSViewRepresentable {
    let colors: [NSColor]
    let tagTitle: String
    let categories: [NoteTag]
    let selectedTagIDs: [UUID]
    let chooseTag: (UUID?) -> Void
    let highlighted: Bool
    let lineCenter: CGFloat
    let collapsed: Bool
    var canCollapse = true
    let edit: () -> Void
    let collapse: () -> Void
    let time: () -> Void
    let tags: () -> Void
    let remove: () -> Void
    func makeNSView(context: Context) -> Area { Area() }
    func updateNSView(_ view: Area,context: Context) { view.configuration = self; view.toolTip = tagTitle + " · 点击展开设置"; view.needsDisplay = true }
    final class Area: NSView {
        var configuration: NoteRowSettings?
        var open = false
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let value = configuration else { return }
            if open || value.highlighted {
                NSColor.secondaryLabelColor.withAlphaComponent(0.7).setFill()
                for x: CGFloat in [bounds.midX - 5,bounds.midX,bounds.midX + 5] { NSBezierPath(ovalIn:NSRect(x:x - 1,y:value.lineCenter - 1,width:2,height:2)).fill() }
            } else {
                let colors = value.colors.isEmpty ? [NSColor.secondaryLabelColor] : Array(value.colors.prefix(3))
                for (index,color) in colors.enumerated() {
                    color.withAlphaComponent(0.75).setFill()
                    NSBezierPath(ovalIn:NSRect(x:bounds.midX - CGFloat(colors.count - 1) * 3 + CGFloat(index) * 6 - 2.5,y:value.lineCenter - 2.5,width:5,height:5)).fill()
                }
            }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { present(event) }
        override func rightMouseDown(with event: NSEvent) { present(event) }
        private func present(_ event: NSEvent) {
            guard let value = configuration else { return }
            let menu = NSMenu()
            let tagItem = NSMenuItem(title:"标签：" + value.tagTitle,action:nil,keyEquivalent:"")
            let tagMenu = NSMenu()
            let free = NSMenuItem(title:"未归类",action:#selector(assignTag(_:)),keyEquivalent:""); free.target = self
            free.state = value.selectedTagIDs.isEmpty ? .on : .off; tagMenu.addItem(free)
            for category in value.categories {
                let item = NSMenuItem(title:category.name,action:#selector(assignTag(_:)),keyEquivalent:"")
                item.target = self; item.representedObject = category.id.uuidString
                item.state = value.selectedTagIDs.contains(category.id) ? .on : .off
                item.image = NoteTagContextMenu.Coordinator.swatch(NoteColors.nativeColor(category.color)); tagMenu.addItem(item)
            }
            tagMenu.addItem(.separator())
            let multiple = NSMenuItem(title:"多选标签…",action:#selector(pickTags),keyEquivalent:""); multiple.target = self; tagMenu.addItem(multiple)
            tagItem.submenu = tagMenu; menu.addItem(tagItem); menu.addItem(.separator())
            for (title,selector) in [("编辑正文",#selector(editNote)),(value.collapsed ? "展开正文" : "折叠正文",#selector(collapseNote)),("预计完成时间…",#selector(pickTime)),("删除小记…",#selector(removeNote))] {
                if selector == #selector(collapseNote), !value.canCollapse { continue }
                let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item)
            }
            open = true; needsDisplay = true; displayIfNeeded()
            NSMenu.popUpContextMenu(menu,with:event,for:self)
            open = false; needsDisplay = true
        }
        @objc func assignTag(_ sender: NSMenuItem) { configuration?.chooseTag((sender.representedObject as? String).flatMap(UUID.init(uuidString:))) }
        @objc func pickTags() { configuration?.tags() }
        @objc func editNote() { configuration?.edit() }
        @objc func collapseNote() { configuration?.collapse() }
        @objc func pickTime() { configuration?.time() }
        @objc func removeNote() { configuration?.remove() }
    }
}
