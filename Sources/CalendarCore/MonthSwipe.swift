import Foundation

/// Locks each trackpad gesture to one axis and keeps its momentum from paging again.
public struct MonthSwipe {
    public enum Phase { case began, changed, ended, cancelled }
    public enum Update: Equatable {
        case ignored
        case consumed
        case moved(CGFloat)
        case finished(CGFloat, cancelled: Bool)
    }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    public private(set) var isActive = false
    public var capturesMomentum: Bool { axis == .horizontal }

    public init() {}

    public mutating func reset() { self = MonthSwipe() }

    public mutating func update(x deltaX: CGFloat, y deltaY: CGFloat, phase: Phase, momentum: Bool = false) -> Update {
        if momentum { return axis == .horizontal ? .consumed : .ignored }
        if phase == .began { reset(); isActive = true }
        if phase == .ended || phase == .cancelled {
            guard isActive else { return .ignored }
            x += deltaX
            isActive = false
            return axis == .horizontal ? .finished(x, cancelled:phase == .cancelled) : .ignored
        }
        if !isActive { reset(); isActive = true }
        x += deltaX; y += deltaY
        if axis == .undecided {
            if abs(x) >= 6 && abs(x) > abs(y) * 1.35 { axis = .horizontal }
            else if abs(y) >= 6 && abs(y) > abs(x) * 1.2 { axis = .vertical }
        }
        return axis == .horizontal ? .moved(x) : .ignored
    }

    /// A short movement returns to the same month; every completed swipe advances at most once.
    public static func step(for distance: CGFloat) -> Int {
        guard abs(distance) >= 52 else { return 0 }
        return distance < 0 ? 1 : -1
    }
}
