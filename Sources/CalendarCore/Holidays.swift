import Foundation

public enum WorkStatus: String, Codable { case rest = "休", work = "班" }
public struct Holiday: Equatable, Codable {
    public let name: String
    public let status: WorkStatus
}
public struct HolidayCalendar {
    public static let source = "https://www.beijing.gov.cn/zhengce/zhengcefagui/202511/t20251104_4258873.html"
    public static let supportedYears: Set<Int> = [2026]
    public var coveredYears: Set<Int> = supportedYears
    public var entries: [String: Holiday] = [:]
    public init(engine: CalendarEngine = CalendarEngine()) {
        let ranges = [(1,1,3,"元旦"),(2,15,23,"春节"),(4,4,6,"清明节"),(5,1,5,"劳动节"),(6,19,21,"端午节"),(9,25,27,"中秋节"),(10,1,7,"国庆节")]
        for (m,start,end,name) in ranges { for d in start...end { entries[engine.key(engine.date(2026,m,d))] = Holiday(name:name,status:.rest) } }
        for (m,d) in [(1,4),(2,14),(2,28),(5,9),(9,20),(10,10)] { entries[engine.key(engine.date(2026,m,d))] = Holiday(name:"调休补班",status:.work) }
    }
    public func status(_ date: Date, engine: CalendarEngine) -> Holiday? { entries[engine.key(date)] }
    public func nextBreak(after date: Date, engine: CalendarEngine) -> (date: Date, name: String)? {
        let day = engine.calendar.startOfDay(for:date)
        for n in 0..<370 {
            let candidate = engine.addingDays(n,to:day)
            if let h = status(candidate,engine:engine), h.status == .rest { return (candidate,h.name) }
        }
        return nil
    }
    public func workDays(from: Date, to: Date, engine: CalendarEngine) -> Int? {
        let lo = min(from,to), hi = max(from,to)
        let count = engine.days(from:lo,to:hi)
        // Interval is (start, end]; do not pretend weekends equal holidays in uncovered years.
        guard count <= 36600 else { return nil }
        if count == 0 { return 0 }
        var total = 0
        for n in 1...count {
            let date = engine.addingDays(n,to:lo)
            guard coveredYears.contains(engine.calendar.component(.year,from:date)) else { return nil }
            if let holiday = status(date,engine:engine) { if holiday.status == .work { total += 1 } }
            else if !engine.calendar.isDateInWeekend(date) { total += 1 }
        }
        return total
    }
}
