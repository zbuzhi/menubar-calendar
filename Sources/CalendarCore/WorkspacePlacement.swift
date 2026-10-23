import Foundation
import CoreGraphics

public enum SettingsDock: String { case left, right, below }

public struct WorkspacePlacement {
    public let frame: CGRect
    public let dock: SettingsDock
    public var settingsOnLeft: Bool { dock == .left }
    public let settingsWidth: CGFloat
    public let calendarHeight: CGFloat
    public let settingsHeight: CGFloat

    public init(anchor: CGRect, visibleFrame: CGRect, calendarHeight requested: CGFloat, settings: Bool) {
        let width: CGFloat = 420
        let top = min(anchor.minY - 6, visibleFrame.maxY - 4)
        let heightLimit = max(100, top - visibleFrame.minY - 4)
        let calendarX = min(max(anchor.maxX - width, visibleFrame.minX), visibleFrame.maxX - width)
        let leftRoom = calendarX - visibleFrame.minX
        let rightRoom = visibleFrame.maxX - calendarX - width
        // Keep the calendar anchored when a side is spacious enough. On narrower
        // screens, use two scrollable regions below one another instead of clipping.
        let sideRoom = max(leftRoom,rightRoom)
        dock = settings && sideRoom < 400 && visibleFrame.width < 940 ? .below : leftRoom > rightRoom ? .left : .right
        let totalHeight: CGFloat
        let totalWidth: CGFloat
        if settings && dock == .below {
            settingsWidth = min(620,visibleFrame.width - 8)
            totalWidth = max(width,settingsWidth)
            totalHeight = min(heightLimit,max(680,requested + 300))
            calendarHeight = min(requested,max(180,(totalHeight - 1) * 0.53))
            settingsHeight = totalHeight - calendarHeight - 1
        } else {
            settingsWidth = min(620,max(320,sideRoom - 1),max(0,visibleFrame.width - width - 1))
            totalWidth = width + (settings ? settingsWidth + 1 : 0)
            totalHeight = min(heightLimit,settings ? max(480,requested) : requested)
            calendarHeight = totalHeight
            settingsHeight = totalHeight
        }
        let proposedX = calendarX - (settings && dock == .left ? settingsWidth + 1 : 0)
        let x = min(max(proposedX,visibleFrame.minX),visibleFrame.maxX - totalWidth)
        frame = CGRect(x:x,y:top - totalHeight,width:totalWidth,height:totalHeight)
    }
}
