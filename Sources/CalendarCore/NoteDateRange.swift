import Foundation

public enum NoteDateNavigationRegion {
    public static func contains(_ point: CGPoint,titleBounds: CGRect,expanded: Bool) -> Bool {
        if titleBounds.insetBy(dx:-4,dy:0).contains(point) { return true }
        // The title and right-side buttons form one horizontal hit region.
        let controls = CGRect(x:titleBounds.minX - 6,y:titleBounds.minY,width:titleBounds.width + 94,height:titleBounds.height)
        return expanded && controls.contains(point)
    }
}

public enum NoteDateScope: String, CaseIterable {
    case day, week, month, custom, all

    public func shiftedAnchor(_ anchor: Date,by delta: Int,calendar: Calendar) -> Date? {
        switch self {
        case .day: return calendar.date(byAdding:.day,value:delta,to:anchor)
        case .week: return calendar.date(byAdding:.day,value:delta * 7,to:anchor)
        case .month:
            // Navigate whole months without accumulating end-of-month clamping.
            guard let first = calendar.date(from:calendar.dateComponents([.year,.month],from:anchor)) else { return nil }
            return calendar.date(byAdding:.month,value:delta,to:first)
        case .custom,.all: return nil
        }
    }
}
public struct NoteDateRange: Equatable {
    public let start: String?
    public let end: String?
    public init(scope: NoteDateScope,anchor: Date,from: Date,through: Date,engine: CalendarEngine = CalendarEngine()) {
        let calendar = engine.calendar
        switch scope {
        case .all: start = nil; end = nil
        case .day: start = engine.key(anchor); end = start
        case .week:
            let day = calendar.startOfDay(for:anchor)
            let offset = (calendar.component(.weekday,from:day) + 5) % 7
            let first = calendar.date(byAdding:.day,value:-offset,to:day)!
            start = engine.key(first); end = engine.key(calendar.date(byAdding:.day,value:6,to:first)!)
        case .month:
            let first = calendar.date(from:calendar.dateComponents([.year,.month],from:anchor))!
            start = engine.key(first)
            end = engine.key(calendar.date(byAdding:.day,value:-1,to:calendar.date(byAdding:.month,value:1,to:first)!)!)
        case .custom: start = engine.key(min(from,through)); end = engine.key(max(from,through))
        }
    }
    public func contains(_ key: String) -> Bool { (start == nil || key >= start!) && (end == nil || key <= end!) }

    public func title(scope: NoteDateScope,anchor: Date,now: Date = Date(),engine: CalendarEngine = CalendarEngine()) -> String {
        switch scope {
        case .day:
            return engine.format(anchor,engine.calendar.isDate(anchor,equalTo:now,toGranularity:.year) ? "M月d日" : "yyyy年M月d日")
        case .month: return engine.format(anchor,"yyyy年M月")
        case .all: return "全部日期"
        case .week,.custom:
            guard let start, let end else { return "" }
            let showYear = start.prefix(4) != end.prefix(4) || start.prefix(4) != engine.key(now).prefix(4)
            func label(_ key: String) -> String { (showYear ? key : String(key.suffix(5))).replacingOccurrences(of:"-",with:"/") }
            return label(start) + "–" + label(end)
        }
    }

    public func dateBounds(engine: CalendarEngine = CalendarEngine()) -> ClosedRange<Date>? {
        func date(_ key: String?) -> Date? {
            let parts = key?.split(separator:"-").compactMap { Int($0) } ?? []
            return parts.count == 3 ? engine.calendar.startOfDay(for:engine.date(parts[0],parts[1],parts[2])) : nil
        }
        guard let first = date(start), let last = date(end),
              let next = engine.calendar.date(byAdding:.day,value:1,to:last) else { return nil }
        return first...next.addingTimeInterval(-1)
    }
    public func insertionDate(anchor: Date,now: Date = Date(),engine: CalendarEngine = CalendarEngine()) -> Date {
        if contains(engine.key(now)) { return engine.calendar.startOfDay(for:now) }
        guard let bounds = dateBounds(engine:engine) else { return engine.calendar.startOfDay(for:anchor) }
        return engine.calendar.startOfDay(for:min(bounds.upperBound,max(bounds.lowerBound,anchor)))
    }
}
