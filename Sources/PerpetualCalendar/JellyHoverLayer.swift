import SwiftUI
import QuartzCore
import CalendarCore

struct DayCellFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String:CGRect], nextValue: () -> [String:CGRect]) { value.merge(nextValue(),uniquingKeysWith: { _,new in new }) }
}

/// Native pointer tracking isolates animation from the expensive date/text view tree.
struct JellyHoverLayer: NSViewRepresentable {
    let frames: [CGRect]
    let color: NSColor
    let mode: String
    func makeNSView(context: Context) -> HoverTrackingView { HoverTrackingView() }
    func updateNSView(_ view: HoverTrackingView, context: Context) { view.configure(frames:frames,color:color,mode:mode) }
}

final class HoverTrackingView: NSView {
    private var cellFrames: [CGRect] = []
    private var tracking: NSTrackingArea?
    private var ticker: Timer?
    private var spring = HoverSpring(position:.zero)
    private var cellSize = CGSize.zero
    private var targetSize = CGSize.zero
    private var opacity = 0.0
    private var visible = false
    private var lastTime = 0.0
    private var mode = "soft"
    private var pointer: CGPoint?
    private let lens: NSView
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = 11
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            lens = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow; material.blendingMode = .withinWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = 11; material.layer?.masksToBounds = true
            lens = material
        }
        super.init(frame:frame)
        wantsLayer = true
        addSubview(lens)
        lens.alphaValue = 0
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func configure(frames: [CGRect], color: NSColor, mode: String) {
        cellFrames = frames
        self.mode = mode
        if #available(macOS 26.0, *), let glass = lens as? NSGlassEffectView { glass.tintColor = color.withAlphaComponent(0.12) }
        else { lens.layer?.backgroundColor = color.withAlphaComponent(0.09).cgColor }
        if let pointer { retarget(pointer) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { retarget(convert(event.locationInWindow,from:nil)) }
    override func mouseMoved(with event: NSEvent) { retarget(convert(event.locationInWindow,from:nil)) }
    override func mouseExited(with event: NSEvent) { pointer = nil; visible = false; startTicker() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTicker(); visible = false; opacity = 0; lens.alphaValue = 0; pointer = nil }
    }
    private func retarget(_ point: CGPoint) {
        pointer = point
        guard let first = cellFrames.first else { return }
        let area = cellFrames.dropFirst().reduce(first) { $0.union($1) }
        guard area.contains(point), let cell = cellFrames.min(by:{ distance(point,$0) < distance(point,$1) }) else { visible = false; startTicker(); return }
        let center = CGPoint(x:cell.midX,y:cell.midY)
        let target = CGPoint(x:center.x + min(2.5,max(-2.5,(point.x-center.x)*0.08)),y:center.y + min(2.5,max(-2.5,(point.y-center.y)*0.08)))
        if opacity < 0.01 { spring = HoverSpring(position:target); cellSize = cell.insetBy(dx:1,dy:1).size }
        spring.target = target
        targetSize = cell.insetBy(dx:1,dy:1).size
        visible = true
        if mode == "off" {
            spring = HoverSpring(position:target); cellSize = targetSize; opacity = 1; drawFrame(); stopTicker()
        } else { startTicker() }
    }
    private func distance(_ point: CGPoint,_ rect: CGRect) -> CGFloat { hypot(point.x-rect.midX,point.y-rect.midY) }
    private func startTicker() {
        guard ticker == nil else { return }
        lastTime = CACurrentMediaTime()
        let fps = min(120,max(60,window?.screen?.maximumFramesPerSecond ?? 60))
        let timer = Timer(timeInterval:1/Double(fps),repeats:true) { [weak self] _ in self?.tick() }
        ticker = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func tick() {
        guard window?.isVisible == true else { stopTicker(); pointer = nil; visible = false; opacity = 0; lens.alphaValue = 0; return }
        let now = CACurrentMediaTime(), dt = min(0.05,max(0,now-lastTime)); lastTime = now
        spring.step(seconds:dt,response:mode == "jelly" ? 0.28 : 0.23,damping:mode == "jelly" ? 0.82 : 0.96)
        let blend = 1-exp(-dt*24)
        cellSize.width += (targetSize.width-cellSize.width)*blend
        cellSize.height += (targetSize.height-cellSize.height)*blend
        opacity += ((visible ? 1.0 : 0.0)-opacity)*(1-exp(-dt*22))
        drawFrame()
        if spring.isSettled && abs(opacity-(visible ? 1 : 0)) < 0.005 { stopTicker() }
    }
    private func drawFrame() {
        let factor = mode == "jelly" ? 1.0 : 0.3
        let sx = 1 + factor*(min(0.16,abs(spring.velocity.dx)/2200)-min(0.045,abs(spring.velocity.dy)/6500))
        let sy = 1 + factor*(min(0.14,abs(spring.velocity.dy)/2200)-min(0.045,abs(spring.velocity.dx)/6500))
        let size = CGSize(width:cellSize.width*sx,height:cellSize.height*sy)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        lens.frame = CGRect(x:spring.position.x-size.width/2,y:spring.position.y-size.height/2,width:size.width,height:size.height)
        lens.alphaValue = opacity
        CATransaction.commit()
    }
}
