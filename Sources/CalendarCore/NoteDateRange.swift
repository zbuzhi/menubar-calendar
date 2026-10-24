import Foundation

public enum NoteDateScope: String, CaseIterable { case day, week, month, custom, all }
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
}
