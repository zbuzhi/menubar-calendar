import Foundation

public struct SolarTerm: Identifiable, Equatable {
    public let index: Int
    public let date: Date
    public var id: Date { date }
    public var name: String { SolarTerms.names[index] }
}

public enum SolarTerms {
    public static let names = ["小寒","大寒","立春","雨水","惊蛰","春分","清明","谷雨","立夏","小满","芒种","夏至","小暑","大暑","立秋","处暑","白露","秋分","寒露","霜降","立冬","小雪","大雪","冬至"]
    private static let lock = NSLock()
    private static var cache: [Int: [SolarTerm]] = [:]
    // Apparent geocentric solar longitude, low-order Meeus/NOAA model.
    // Dates are suitable for a calendar; precise term times are approximate (minutes).
    public static func longitude(_ date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545) / 36525
        let mean = 280.46646 + t * (36000.76983 + 0.0003032 * t)
        let anomaly = (357.52911 + t * (35999.05029 - 0.0001537 * t)) * .pi / 180
        let equation = sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * anomaly) * (0.019993 - 0.000101 * t) + sin(3 * anomaly) * 0.000289
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        let value = mean + equation - 0.00569 - 0.00478 * sin(omega)
        return (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
    public static func events(year: Int, engine: CalendarEngine = CalendarEngine()) -> [SolarTerm] {
        lock.lock(); let cached = cache[year]; lock.unlock()
        if let cached { return cached }
        let results = (0..<24).map { i -> SolarTerm in
            let target = Double((285 + i * 15) % 360)
            let month = i / 2 + 1
            var low = engine.date(year, month, i % 2 == 0 ? 1 : 15, hour: 0).timeIntervalSince1970
            var high = low + 12 * 86400
            for _ in 0..<40 {
                let mid = (low + high) / 2
                let angle = longitude(Date(timeIntervalSince1970: mid))
                let delta = (angle - target + 540).truncatingRemainder(dividingBy: 360) - 180
                if delta < 0 { low = mid } else { high = mid }
            }
            return SolarTerm(index: i, date: Date(timeIntervalSince1970: (low + high) / 2))
        }
        lock.lock(); cache[year] = results; lock.unlock()
        return results
    }
    public static func surrounding(_ date: Date, engine: CalendarEngine) -> (current: SolarTerm, next: SolarTerm) {
        let year = engine.calendar.component(.year, from: date)
        let all = events(year: year - 1, engine: engine) + events(year: year, engine: engine) + events(year: year + 1, engine: engine)
        // Day-based UI deliberately treats the whole local term date as day one.
        let day = engine.calendar.startOfDay(for: date)
        let current = all.last { engine.calendar.startOfDay(for: $0.date) <= day }!
        let next = all.first { engine.calendar.startOfDay(for: $0.date) > day }!
        return (current, next)
    }
    public static func on(_ date: Date, engine: CalendarEngine) -> SolarTerm? {
        events(year: engine.calendar.component(.year, from: date), engine: engine).first { engine.calendar.isDate($0.date, inSameDayAs: date) }
    }
}

public struct MoonPhase {
    public let fraction: Double
    public let age: Double
    public let illumination: Double
    public var name: String {
        switch fraction {
        case ..<0.035, 0.965...: return "新月"
        case ..<0.215: return "娥眉月"
        case ..<0.285: return "上弦月"
        case ..<0.465: return "盈凸月"
        case ..<0.535: return "满月"
        case ..<0.715: return "亏凸月"
        case ..<0.785: return "下弦月"
        default: return "残月"
        }
    }
    public init(date: Date) {
        let period = 29.530588853
        let cycles = (date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451550.25972) / period
        fraction = cycles - floor(cycles)
        age = fraction * period
        illumination = (1 - cos(2 * .pi * fraction)) / 2
    }
}
