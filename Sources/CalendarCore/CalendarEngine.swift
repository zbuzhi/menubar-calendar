import Foundation

public struct LunarDate: Equatable {
    public let year: Int
    public let cycleYear: Int
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool
    public var yearName: String { CalendarEngine.stems[(cycleYear - 1) % 10] + CalendarEngine.branches[(cycleYear - 1) % 12] }
    public var animal: String { CalendarEngine.animals[(cycleYear - 1) % 12] }
    public var monthName: String { (isLeapMonth ? "闰" : "") + ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"][month - 1] + "月" }
    public var dayName: String {
        if day == 10 { return "初十" }; if day == 20 { return "二十" }; if day == 30 { return "三十" }
        return ["初", "十", "廿"][min(2, (day - 1) / 10)] + ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][(day - 1) % 10]
    }
    public var short: String { day == 1 ? monthName : dayName }
}

public struct YearProgress {
    public let start: Date
    public let end: Date
    public let day: Int
    public let total: Int
    public let fraction: Double
    public var remaining: Int { total - day }
}

public struct Zodiac: Equatable {
    public let index: Int
    public let name: String
    public let start: Date
    public let day: Int
}

public struct CalendarEngine {
    public static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    public static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)
    public static let animals = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪").map(String.init)
    public var calendar: Calendar
    public var chinese: Calendar
    public init(timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
    }
    public func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
    public func key(_ date: Date) -> String { format(date, "yyyy-MM-dd") }
    public func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "zh_CN"); f.dateFormat = pattern
        return f.string(from: date)
    }
    public func lunar(_ date: Date) -> LunarDate {
        let c = chinese.dateComponents([.year, .month, .day], from: date)
        let start = chinese.dateInterval(of: .year, for: date)!.start
        return LunarDate(year: calendar.component(.year, from: start), cycleYear: c.year!, month: c.month!, day: c.day!, isLeapMonth: c.isLeapMonth ?? false)
    }
    public func days(from: Date, to: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day!
    }
    public func addingDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date)! }
    public func monthDays(_ month: Date, mondayFirst: Bool = true) -> [Date] {
        let first = calendar.dateInterval(of: .month, for: month)!.start
        let offset = (calendar.component(.weekday, from: first) - (mondayFirst ? 2 : 1) + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        let cells = ((offset + count + 6) / 7) * 7
        return (0..<cells).map { addingDays($0 - offset, to: first) }
    }
    public func progress(_ date: Date, lunar: Bool) -> YearProgress {
        let c = lunar ? chinese : calendar
        let interval = c.dateInterval(of: .year, for: date)!
        let total = days(from: interval.start, to: interval.end)
        return YearProgress(start: interval.start, end: interval.end, day: days(from: interval.start, to: date) + 1, total: total, fraction: max(0, min(1, date.timeIntervalSince(interval.start) / interval.duration)))
    }
    public func week(_ date: Date, iso: Bool) -> (year: Int, week: Int) {
        var c = calendar; c.firstWeekday = 2; c.minimumDaysInFirstWeek = iso ? 4 : 1
        if iso { return (c.component(.yearForWeekOfYear, from: date), c.component(.weekOfYear, from: date)) }
        let start = calendar.dateInterval(of: .year, for: date)!.start
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        return (calendar.component(.year, from: date), (days(from: start, to: date) + offset) / 7 + 1)
    }
    public func zodiac(_ date: Date) -> Zodiac {
        let names = ["摩羯座", "水瓶座", "双鱼座", "白羊座", "金牛座", "双子座", "巨蟹座", "狮子座", "处女座", "天秤座", "天蝎座", "射手座"]
        let boundaries = [(1,20),(2,19),(3,21),(4,20),(5,21),(6,22),(7,23),(8,23),(9,23),(10,23),(11,23),(12,22)]
        let y = calendar.component(.year, from: date)
        let day = calendar.startOfDay(for: date)
        var index = 0; var start = self.date(y - 1, 12, 22, hour: 0)
        for (i, bound) in boundaries.enumerated() {
            let candidate = self.date(y, bound.0, bound.1, hour: 0)
            if day >= candidate { index = (i + 1) % 12; start = candidate }
        }
        return Zodiac(index: index, name: names[index], start: start, day: days(from: start, to: date) + 1)
    }
    // 96-ke convention: a two-hour branch contains eight 15-minute intervals.
    public func traditionalTime(_ date: Date, detailed: Bool = true) -> String {
        let h = calendar.component(.hour, from: date), m = calendar.component(.minute, from: date)
        let branch = Self.branches[((h + 1) / 2) % 12]
        guard detailed else { return branch + "时" }
        let elapsed = ((h + 1) % 2) * 60 + m
        return branch + "时" + ["初刻", "一刻", "二刻", "三刻", "四刻", "五刻", "六刻", "七刻"][elapsed / 15]
    }
    public func stemDay(_ date: Date) -> String {
        let delta = days(from: self.date(2000, 1, 7), to: date)
        let n = (delta % 60 + 60) % 60
        return Self.stems[n % 10] + Self.branches[n % 12] + "日"
    }
    public func stemMonth(_ date: Date) -> String {
        // Solar months change at the twelve jie terms, independent of lunar month boundaries.
        let y = calendar.component(.year, from: date)
        let terms = SolarTerms.events(year: y - 1, engine: self) + SolarTerms.events(year: y, engine: self)
        let jie = terms.filter { $0.index % 2 == 0 && $0.date <= date }.last!
        let monthBranch = (jie.index / 2 + 1) % 12
        let spring = SolarTerms.events(year: y, engine: self)[2].date
        let solarYear = date < spring ? y - 1 : y
        let yearStem = ((solarYear - 4) % 10 + 10) % 10
        let offset = (monthBranch - 2 + 12) % 12
        let stem = ((yearStem % 5) * 2 + 2 + offset) % 10
        return Self.stems[stem] + Self.branches[monthBranch] + "月"
    }
    public func festival(_ date: Date) -> String? {
        let md = format(date, "MM-dd")
        let fixed = ["01-01":"元旦", "02-14":"情人节", "03-08":"妇女节", "05-01":"劳动节", "06-01":"儿童节", "10-01":"国庆节", "12-25":"圣诞节"]
        let l = lunar(date)
        if !l.isLeapMonth {
            let festivals = ["1-1":"春节", "1-15":"元宵节", "5-5":"端午节", "7-7":"七夕", "8-15":"中秋节", "9-9":"重阳节", "12-8":"腊八节"]
            if let name = festivals["\(l.month)-\(l.day)"] { return name }
            let next = lunar(addingDays(1, to: date)); if l.month == 12 && next.month == 1 && next.day == 1 { return "除夕" }
        }
        return fixed[md]
    }
}
