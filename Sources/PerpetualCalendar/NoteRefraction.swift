import AppKit
import SwiftUI
import CoreImage

/// Refracts the rendered text pixels locally using the system's GPU-backed image filters.
/// A snapshot is taken once per hover/size/content change; pointer updates only reuse that texture.
struct NoteRefraction: NSViewRepresentable {
    let active: Bool
    let revision: String
    func makeNSView(context: Context) -> Lens { Lens() }
    func updateNSView(_ view: Lens,context: Context) { view.configure(active:active,revision:revision) }
    static func dismantleNSView(_ view: Lens,coordinator: ()) { view.clear() }
    final class Lens: NSView {
        private static let renderer = CIContext(options:[.cacheIntermediates:false])
        private var enabled = false
        private var revision = ""
        private var tracking: NSTrackingArea?
        private var source: CIImage?
        private var output: CGImage?
        private var capturedRect = CGRect.zero
        private var capturedWindowRect = CGRect.zero
        private var scale: CGFloat = 1
        private var pending: DispatchWorkItem?
        private var lastRender = 0.0
        private(set) var snapshotCount = 0
        private(set) var renderMilliseconds = 0.0
        private var point: CGPoint?
        override var isFlipped: Bool { true }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func configure(active: Bool,revision: String) {
            if self.revision != revision { clear(); self.revision = revision }
            let entering = active && !enabled
            enabled = active
            if !active { clear() }
            else if entering, let window {
                let location = convert(window.mouseLocationOutsideOfEventStream,from:nil)
                if bounds.contains(location) { point = location; schedule(minimumDelay:0.08) }
            }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if source != nil, convert(capturedRect,to:nil) != capturedWindowRect { clear() }
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect:.zero,options:[.activeAlways,.inVisibleRect,.mouseMoved,.mouseEnteredAndExited],owner:self)
            addTrackingArea(area); tracking = area
        }
        override func mouseEntered(with event: NSEvent) { move(event) }
        override func mouseMoved(with event: NSEvent) { move(event) }
        override func mouseExited(with event: NSEvent) { clear() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { clear() } }
        override func setFrameSize(_ newSize: NSSize) { if newSize != frame.size { clear() }; super.setFrameSize(newSize) }
        private func move(_ event: NSEvent) {
            guard enabled else { return }
            point = convert(event.locationInWindow,from:nil)
            schedule(minimumDelay:0)
        }
        private func schedule(minimumDelay: Double) {
            guard pending == nil else { return }
            let frameInterval = 1.0 / (renderMilliseconds <= 4 ? 60.0 : 30.0)
            let delay = max(minimumDelay,frameInterval - (ProcessInfo.processInfo.systemUptime - lastRender))
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }; self.pending = nil
                self.render()
            }
            pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
        }
        private func capture() {
            guard window != nil, !bounds.isEmpty else { return }
            var root: NSView = self
            while let parent = root.superview { root = parent }
            var rect = bounds.intersection(visibleRect)
            var ancestor = superview
            while let parent = ancestor {
                rect = rect.intersection(convert(parent.bounds,from:parent)); ancestor = parent.superview
            }
            guard rect.width > 1, rect.height > 1 else { return }
            let region = convert(rect,to:root)
            // Hide only this drawing layer so caching cannot capture its previous refracted frame.
            isHidden = true
            defer { isHidden = false }
            guard let bitmap = root.bitmapImageRepForCachingDisplay(in:region) else { return }
            root.cacheDisplay(in:region,to:bitmap)
            guard let image = bitmap.cgImage else { return }
            capturedRect = rect; capturedWindowRect = convert(rect,to:nil); scale = CGFloat(image.width) / rect.width
            source = CIImage(cgImage:image); snapshotCount += 1
        }
        private func render() {
            guard enabled, let point, bounds.contains(point), window?.isVisible == true else { return }
            if source == nil { capture() }
            guard let source, let filter = CIFilter(name:"CIBumpDistortion") else { return }
            let center = CIVector(x:(point.x - capturedRect.minX) * scale,y:(capturedRect.maxY - point.y) * scale)
            filter.setValue(source,forKey:kCIInputImageKey)
            filter.setValue(center,forKey:kCIInputCenterKey)
            filter.setValue(48 * scale,forKey:kCIInputRadiusKey)
            filter.setValue(0.16,forKey:kCIInputScaleKey)
            guard let result = filter.outputImage else { return }
            let began = ProcessInfo.processInfo.systemUptime
            output = Self.renderer.createCGImage(result.cropped(to:source.extent),from:source.extent)
            lastRender = ProcessInfo.processInfo.systemUptime; renderMilliseconds = (lastRender - began) * 1000; needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let output, let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.translateBy(x:capturedRect.minX,y:capturedRect.maxY); context.scaleBy(x:1,y:-1)
            context.draw(output,in:CGRect(origin:.zero,size:capturedRect.size))
            context.restoreGState()
        }
        func clear() { pending?.cancel(); pending = nil; source = nil; output = nil; point = nil; needsDisplay = true }
    }
}
