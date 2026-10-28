import AppKit
import SwiftUI
import CalendarCore

/// Local mouse tracking avoids pasteboard/drop negotiation and keeps one uninterrupted native drag session.
struct NoteTabStrip: NSViewRepresentable {
    let tags: [NoteTag]
    let selected: UUID?
    let accent: NSColor
    let mode: String
    let select: (UUID?) -> Void
    let move: (UUID,UUID) -> Void
    let context: (NoteTag) -> NSMenu
    var wraps = false
    var maximumHeight: CGFloat = 260
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FlowScroll(); scroll.drawsBackground = false
        scroll.hasVerticalScroller = wraps; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.documentView = StripView(); return scroll
    }
    func updateNSView(_ scroll: NSScrollView,context: Context) {
        (scroll.documentView as? StripView)?.configure(self,viewport:scroll.contentSize.width)
    }
    func sizeThatFits(_ proposal: ProposedViewSize,nsView: NSScrollView,context: Context) -> CGSize? {
        guard wraps, let width = proposal.width, width > 0 else { return nil }
        let frames = Self.frames(tags:tags,selected:selected,width:width,wraps:true)
        return CGSize(width:width,height:min(maximumHeight,frames.map(\.maxY).max() ?? 32))
    }
    static func frames(tags: [NoteTag],selected: UUID?,width: CGFloat,wraps: Bool) -> [CGRect] {
        let values: [(UUID?,String)] = [(nil,"全部")] + tags.map { ($0.id,$0.name) }
        var x: CGFloat = 0, y: CGFloat = 0
        return values.map { id,name in
            let font = NSFont.systemFont(ofSize:12,weight:id == selected ? .semibold : .regular)
            let natural = ceil((name as NSString).size(withAttributes:[.font:font]).width) + (id == nil ? 24 : 34)
            let w = wraps ? min(width,natural) : natural
            if wraps, x > 0, x + w > width { x = 0; y += 36 }
            let rect = CGRect(x:x,y:y,width:w,height:32); x += w + 4; return rect
        }
    }
    final class FlowScroll: NSScrollView {
        override func layout() {
            super.layout()
            if let strip = documentView as? StripView, let value = strip.configuration,
               value.wraps, abs(strip.bounds.width - contentSize.width) > 0.5 {
                strip.configure(value,viewport:contentSize.width)
            }
        }
    }
    final class StripView: NSView {
        override var isFlipped: Bool { true }
        private let hover = HoverTrackingView()
        private var buttons: [TabView] = []
        var configuration: NoteTabStrip?
        override init(frame: NSRect) { super.init(frame:frame); addSubview(hover) }
        required init?(coder: NSCoder) { fatalError() }
        func configure(_ value: NoteTabStrip,viewport: CGFloat) {
            configuration = value
            let values: [(UUID?,String,NSColor?)] = [(nil,"全部",nil)] + value.tags.map { ($0.id,$0.name,NoteColors.nativeColor($0.color)) }
            let old = buttons; var next: [TabView] = []
            let frames = NoteTabStrip.frames(tags:value.tags,selected:value.selected,width:max(1,viewport),wraps:value.wraps)
            for (index,item) in values.enumerated() {
                let (id,name,color) = item
                let button = old.first { $0.id == id } ?? TabView()
                button.id = id; button.title = name; button.color = color; button.strip = self
                button.selected = id == value.selected; button.accent = value.accent
                button.toolTip = id == nil ? "全部小记" : "长按拖动排序 · 右键管理"
                button.setAccessibilityElement(true); button.setAccessibilityRole(.button); button.setAccessibilityLabel(name)
                button.setAccessibilityValue(button.selected ? "已选中" : "未选中")
                if button.superview == nil { addSubview(button) }
                button.frame = frames[index]; button.needsDisplay = true
                next.append(button)
            }
            for button in old where !next.contains(where:{ $0 === button }) { button.removeFromSuperview() }
            buttons = next
            frame.size = NSSize(width:value.wraps ? viewport : max(viewport,frames.map(\.maxX).max() ?? 0),height:frames.map(\.maxY).max() ?? 32)
            hover.frame = bounds; hover.configure(frames:buttons.map(\.frame),color:value.accent,mode:value.mode)
        }
        func drag(_ id: UUID,to point: NSPoint) {
            guard let target = buttons.filter({ $0.id != nil }).min(by:{ hypot($0.frame.midX - point.x,$0.frame.midY - point.y) < hypot($1.frame.midX - point.x,$1.frame.midY - point.y) }),
                  let targetID = target.id, id != targetID else { return }
            if var value = configuration, let source = value.tags.firstIndex(where:{ $0.id == id }), let destination = value.tags.firstIndex(where:{ $0.id == targetID }) {
                var tags = value.tags; let tag = tags.remove(at:source); tags.insert(tag,at:destination)
                value = NoteTabStrip(tags:tags,selected:value.selected,accent:value.accent,mode:value.mode,select:value.select,move:value.move,context:value.context)
                configure(value,viewport:enclosingScrollView?.contentSize.width ?? bounds.width)
                value.move(id,targetID)
            }
        }
        final class TabView: NSView {
            var id: UUID?
            var title = ""
            var color: NSColor?
            var accent = NSColor.systemBlue
            var selected = false
            weak var strip: StripView?
            override var isFlipped: Bool { true }
            override func draw(_ dirtyRect: NSRect) {
                if selected { accent.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:15,yRadius:15).fill() }
                let font = NSFont.systemFont(ofSize:12,weight:selected ? .semibold : .regular)
                let size = (title as NSString).size(withAttributes:[.font:font])
                if let color { color.setFill(); NSBezierPath(ovalIn:NSRect(x:11,y:13.5,width:5,height:5)).fill() }
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
                let left: CGFloat = color == nil ? 12 : 22
                (title as NSString).draw(in:NSRect(x:left,y:(bounds.height - size.height)/2,width:max(0,bounds.width - left - 8),height:size.height),
                                        withAttributes:[.font:font,.paragraphStyle:style,.foregroundColor:selected ? accent : NSColor.secondaryLabelColor])
            }
            override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            override func mouseDown(with event: NSEvent) {
                guard let strip, let window else { return }
                if event.modifierFlags.contains(.control) { rightMouseDown(with:event); return }
                let sourceID = id; let start = event.locationInWindow; var dragging = false
                while let next = window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp],until:.distantFuture,inMode:.eventTracking,dequeue:true) {
                    if next.type == .leftMouseUp { if !dragging { strip.configuration?.select(sourceID) }; break }
                    if let sourceID, next.timestamp - event.timestamp >= 0.28, hypot(next.locationInWindow.x - start.x,next.locationInWindow.y - start.y) > 4 {
                        if !dragging { NSCursor.closedHand.push() }
                        dragging = true; strip.drag(sourceID,to:strip.convert(next.locationInWindow,from:nil))
                        strip.hover.mouseMoved(with:next)
                    }
                }
                if dragging { NSCursor.pop() }
            }
            override var acceptsFirstResponder: Bool { true }
            override func accessibilityPerformPress() -> Bool { strip?.configuration?.select(id); return true }
            override func keyDown(with event: NSEvent) {
                if event.keyCode == 36 || event.keyCode == 49 { strip?.configuration?.select(id) } else { super.keyDown(with:event) }
            }
            override func rightMouseDown(with event: NSEvent) {
                guard let id, let strip, let tag = strip.configuration?.tags.first(where:{ $0.id == id }), let menu = strip.configuration?.context(tag) else { return }
                NSMenu.popUpContextMenu(menu,with:event,for:self)
            }
        }
    }
}

struct NoteIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.padding(4).modifier(NoteIconHover(pressed:configuration.isPressed)) }
}
struct NoteIconHover: ViewModifier {
    var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.background(.primary.opacity(pressed ? 0.09 : hovered ? 0.045 : 0),in:RoundedRectangle(cornerRadius:6))
            .scaleEffect(pressed && !reduced ? 0.98 : 1)
            .animation(reduced ? nil : .easeOut(duration:0.12),value:hovered)
            .animation(reduced ? nil : .easeOut(duration:0.08),value:pressed)
            .onHover { hovered = $0 }
    }
}
