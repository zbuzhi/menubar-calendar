import AppKit
import SwiftUI
import CalendarCore

struct NoteDateAnchor: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?,nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

/// A single native view owns the date and real buttons, entirely inside the header's bounds.
struct NoteNativeDateNavigation: NSViewRepresentable {
    let title: String
    let fullTitle: String
    let titleWidth: CGFloat
    let expanded: Bool
    let navigable: Bool
    let current: Bool
    let unit: String
    let currentTitle: String
    let background: NSColor
    let open: () -> Void
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void
    let hovered: (Bool) -> Void
    func makeNSView(context: Context) -> Area { Area() }
    func updateNSView(_ view: Area,context: Context) { view.configure(self) }
    static func dismantleNSView(_ view: Area,coordinator: ()) { view.stop() }

    final class Area: NSView {
        private var configuration: NoteNativeDateNavigation?
        private let dateButton = NSButton(title:"",target:nil,action:nil)
        private var arrows: [NSButton] = []
        private var monitor: Any?
        private var timer: Timer?
        private var inside = false
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame:frame)
            dateButton.isBordered = false; dateButton.alignment = .left
            dateButton.font = .systemFont(ofSize:11); dateButton.contentTintColor = .secondaryLabelColor
            dateButton.target = self; dateButton.action = #selector(openRange)
            (dateButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            addSubview(dateButton)
            for (symbol,action) in [("chevron.left",#selector(goPrevious)),("chevron.right",#selector(goNext)),("arrow.uturn.backward",#selector(goToday))] {
                let button = NSButton(image:NSImage(systemSymbolName:symbol,accessibilityDescription:nil)!,target:self,action:action)
                button.bezelStyle = .recessed; button.showsBorderOnlyWhileMouseInside = true
                button.imagePosition = .imageOnly; button.contentTintColor = .secondaryLabelColor
                button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize:11,weight:.medium)
                arrows.append(button); addSubview(button)
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ value: NoteNativeDateNavigation) {
            configuration = value
            dateButton.attributedTitle = NSAttributedString(string:value.title,attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:value.expanded ? NSColor.labelColor : NSColor.secondaryLabelColor])
            dateButton.toolTip = value.fullTitle + " · 选择日期范围"
            dateButton.setAccessibilityLabel(value.fullTitle + "，选择日期范围")
            dateButton.frame = NSRect(x:6,y:0,width:value.titleWidth,height:28)
            let labels = ["上一" + value.unit,"下一" + value.unit,"返回" + value.currentTitle]
            for (index,button) in arrows.enumerated() {
                button.frame = NSRect(x:value.titleWidth + 10 + CGFloat(index) * 26,y:0,width:26,height:28)
                button.isHidden = !value.expanded || !value.navigable || (index == 2 && value.current)
                button.toolTip = labels[index]; button.setAccessibilityLabel(labels[index])
            }
            needsDisplay = true
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let configuration, configuration.expanded && configuration.navigable else { return }
            let capsule = NSRect(x:0,y:0,width:configuration.titleWidth + (configuration.current ? 68 : 94),height:bounds.height)
            let path = NSBezierPath(roundedRect:capsule.insetBy(dx:0.5,dy:0.5),xRadius:14,yRadius:14)
            configuration.background.setFill(); path.fill()
            NSColor.labelColor.withAlphaComponent(0.035).setFill(); path.fill()
            NSColor.labelColor.withAlphaComponent(0.07).setStroke(); path.lineWidth = 0.5; path.stroke()
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard let window else { return }
            window.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.leftMouseDown,.leftMouseUp]) { [weak self] event in
                self?.refresh(); return event
            }
        }
        private func refresh() {
            let next: Bool
            if let configuration, configuration.navigable, let window, window.isVisible, !isHiddenOrHasHiddenAncestor {
                let point = convert(window.convertPoint(fromScreen:NSEvent.mouseLocation),from:nil)
                next = NoteDateNavigationRegion.contains(point,titleBounds:dateButton.frame,expanded:configuration.expanded)
            } else { next = false }
            guard next != inside else { return }
            inside = next
            if next {
                let ticker = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in self?.refresh() }
                RunLoop.main.add(ticker,forMode:.common); timer = ticker
            } else { timer?.invalidate(); timer = nil }
            configuration?.hovered(next)
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
            timer?.invalidate(); timer = nil; inside = false
        }
        @objc private func openRange() { configuration?.open() }
        @objc private func goPrevious() { configuration?.hovered(true); configuration?.previous() }
        @objc private func goNext() { configuration?.hovered(true); configuration?.next() }
        @objc private func goToday() { configuration?.hovered(true); configuration?.today() }
    }
}
