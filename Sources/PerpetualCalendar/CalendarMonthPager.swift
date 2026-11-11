import SwiftUI
import CalendarCore

private struct MonthPageHeights: PreferenceKey {
    static var defaultValue: [Date:CGFloat] = [:]
    static func reduce(value: inout [Date:CGFloat], nextValue: () -> [Date:CGFloat]) {
        value.merge(nextValue(),uniquingKeysWith:{ _,new in new })
    }
}

/// The date grids remain separate views so moving them doesn't recalculate every day's labels.
struct CalendarMonthPager<Content: View>: View {
    let month: Date
    let calendar: Calendar
    let reduced: Bool
    let navigate: (Int) -> Void
    @ViewBuilder let content: (Date) -> Content
    private let width: CGFloat = 388
    private let duration = 0.24
    @LocalState private var offset: CGFloat = 0
    @LocalState private var tracking = false
    @LocalState private var settling = false
    @LocalState private var heights: [Date:CGFloat] = [:]
    @LocalState private var completion: Task<Void,Never>?

    private var current: Date { calendar.dateInterval(of:.month,for:month)!.start }
    private func adjacent(_ step: Int) -> Date? {
        guard let date = calendar.date(byAdding:.month,value:step,to:current),
              (1901...2100).contains(calendar.component(.year,from:date)) else { return nil }
        return date
    }
    private var height: CGFloat? {
        guard let start = heights[current] else { return nil }
        guard offset != 0, let next = adjacent(offset < 0 ? 1 : -1), let end = heights[next] else { return start }
        return start + (end - start) * min(1,abs(offset) / width)
    }
    var body: some View {
        page(current)
            .offset(x:reduced ? 0 : offset)
            .overlay(alignment:.topLeading) {
                if !reduced {
                    ForEach([-1,1],id:\.self) { step in
                        if let date = adjacent(step) {
                            page(date).offset(x:CGFloat(step) * width + offset)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }
            }
            .frame(width:width,height:height,alignment:.topLeading)
            .clipped()
            .allowsHitTesting(!tracking && !settling)
            .background(CalendarTrackpadSwipe(enabled:!settling,changed:moved,ended:ended))
            .onPreferenceChange(MonthPageHeights.self) { heights = $0 }
            .onChange(of:month) { _ in reset() }
            .onChange(of:reduced) { _ in reset() }
            .onDisappear { reset() }
    }
    private func page(_ date: Date) -> some View {
        content(date)
            .frame(width:width).fixedSize(horizontal:false,vertical:true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key:MonthPageHeights.self,value:[date:geometry.size.height])
            })
    }
    private func moved(_ distance: CGFloat) {
        guard !settling else { return }
        tracking = true
        guard !reduced else { return }
        let bounded = min(width * 0.98,max(-width * 0.98,distance))
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { offset = adjacent(distance < 0 ? 1 : -1) == nil ? bounded * 0.15 : bounded }
    }
    private func ended(_ distance: CGFloat, _ cancelled: Bool) {
        guard !settling else { return }
        tracking = false
        let proposed = cancelled ? 0 : MonthSwipe.step(for:distance)
        let step = proposed != 0 && adjacent(proposed) != nil ? proposed : 0
        if reduced { if step != 0 { navigate(step) }; return }
        settling = true
        withAnimation(.easeOut(duration:duration)) { offset = -CGFloat(step) * width }
        completion = Task { @MainActor in
            do { try await Task.sleep(nanoseconds:UInt64(duration * 1_000_000_000)) } catch { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                if step != 0 { navigate(step) }
                offset = 0; settling = false; completion = nil
            }
        }
    }
    private func reset() {
        completion?.cancel(); completion = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0; tracking = false; settling = false }
    }
}

/// Observes only phased, precise scrolling over the visible month grid; vertical scrolling stays native.
struct CalendarTrackpadSwipe: NSViewRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, Bool) -> Void
    func makeNSView(context: Context) -> Area { Area() }
    func updateNSView(_ view: Area, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: Area, coordinator: ()) { view.stop() }

    final class Area: NSView {
        var configuration: CalendarTrackpadSwipe?
        private var gesture = MonthSwipe()
        private var monitor: Any?
        private var suppressed = false
        private var inGesture = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.isVisible, !self.isHiddenOrHasHiddenAncestor,
                      event.hasPreciseScrollingDeltas,
                      !event.phase.isEmpty || !event.momentumPhase.isEmpty else { return event }
                let inside = self.visibleRect.contains(self.convert(event.locationInWindow,from:nil))
                // Once a gesture starts here, finish it even if the pointer leaves the grid.
                guard inside || self.gesture.isActive || (!event.momentumPhase.isEmpty && self.gesture.capturesMomentum) else { return event }
                if event.phase.contains(.began) && !inside { return event }
                let phase: MonthSwipe.Phase = event.phase.contains(.cancelled) ? .cancelled :
                    event.phase.contains(.ended) ? .ended : event.phase.contains(.began) ? .began : .changed
                return self.receive(x:event.scrollingDeltaX,y:event.scrollingDeltaY,phase:phase,
                                    momentum:event.phase.isEmpty && !event.momentumPhase.isEmpty) ? nil : event
            }
        }
        @discardableResult func receive(x: CGFloat, y: CGFloat, phase: MonthSwipe.Phase, momentum: Bool = false) -> Bool {
            guard let configuration else { return false }
            if !momentum {
                if phase == .began || (!inGesture && phase == .changed) {
                    gesture.reset(); inGesture = true; suppressed = !configuration.enabled
                }
            }
            defer { if !momentum && (phase == .ended || phase == .cancelled) { inGesture = false } }
            guard !suppressed else { return false }
            switch gesture.update(x:x,y:y,phase:phase,momentum:momentum) {
            case .ignored: return false
            case .consumed: return true
            case .moved(let distance): configuration.changed(distance); return true
            case .finished(let distance,let cancelled): configuration.ended(distance,cancelled); return true
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
            gesture.reset(); suppressed = false; inGesture = false
        }
    }
}
