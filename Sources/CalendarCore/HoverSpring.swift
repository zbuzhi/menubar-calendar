import Foundation
import CoreGraphics

/// Interruptible motion: retargeting preserves velocity instead of restarting a tween.
public struct HoverSpring {
    public private(set) var position: CGPoint
    public private(set) var velocity: CGVector = .zero
    public var target: CGPoint
    public init(position: CGPoint) { self.position = position; target = position }
    public mutating func step(seconds: Double, response: Double, damping: Double) {
        let duration = min(max(seconds,0),0.05)
        let steps = max(1,Int(ceil(duration * 240)))
        let dt = duration / Double(steps)
        let omega = 2 * Double.pi / max(0.1,response)
        for _ in 0..<steps {
            let ax = omega * omega * (target.x - position.x) - 2 * damping * omega * velocity.dx
            let ay = omega * omega * (target.y - position.y) - 2 * damping * omega * velocity.dy
            velocity.dx += ax * dt; velocity.dy += ay * dt
            position.x += velocity.dx * dt; position.y += velocity.dy * dt
        }
    }
    public var isSettled: Bool { hypot(position.x-target.x,position.y-target.y) < 0.04 && hypot(velocity.dx,velocity.dy) < 0.4 }
}
