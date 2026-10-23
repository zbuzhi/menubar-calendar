import Foundation

public enum DateFormats {
    public static let fields: [(String, String)] = [
        ("公历年","yyyy"),("短年","yy"),("汉字年","cnYear"),("汉字短年","cnShortYear"),
        ("月","MM"),("不补零月","M"),("汉字月","cnMonth"),("日","dd"),("不补零日","d"),("汉字日","cnDay"),
        ("星期","weekday"),("短星期","weekShort"),("干支年","ganzhi"),("生肖","animal"),
        ("农历月","lunarMonth"),("农历日","lunarDay"),("农历","lunar"),
        ("时","HH"),("12小时","hh"),("不补零时","H"),("分","mm"),("秒","ss"),("上午下午","ampm"),
        ("时辰","branch"),("时辰与刻","ke"),("节气","term"),("星座","zodiac"),("年内天数","dayOfYear"),("周数","week")
    ]
    public static let presets: [(String, String)] = [
        ("日期与星期", "{M}月{d}日 {weekShort}"),
        ("完整日期时间", "{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}"),
        ("中文日期时间", "{yyyy}年{M}月{d}日 {HH}:{mm}:{ss}"),
        ("带空格中文", "{yyyy} 年 {M} 月 {d} 日 {HH}:{mm}:{ss}"),
        ("点号日期", "{yyyy}.{MM}.{dd}"), ("斜线日期", "{yyyy}/{MM}/{dd} {HH}:{mm}:{ss}"),
        ("汉字短日期", "{cnShortYear}.{cnMonth}.{cnDay}"),
        ("农历干支", "{ganzhi}年{lunar}"), ("传统时间", "{lunar} · {ke}"),
        ("仅时间", "{HH}:{mm}:{ss}"), ("十二小时制", "{ampm} {hh}:{mm}:{ss}"),
        ("仅日期", "{yyyy}-{MM}-{dd}"), ("公农历", "{MM}-{dd}｜{lunar}")
    ]
    public static let copyDefaults = ["{yyyy}年{M}月{d}日 {HH}:{mm}:{ss}", "{yyyy} 年 {M} 月 {d} 日 {HH}:{mm}:{ss}", "{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}", "{yyyy}/{MM}/{dd} {HH}:{mm}:{ss}", "{yyyy}-{MM}-{dd}", "{HH}:{mm}:{ss}"]
    public static func chineseDigits(_ n: Int) -> String {
        let chars = Array("〇一二三四五六七八九")
        return String(n).compactMap { $0.wholeNumberValue.map { chars[$0] } }.map(String.init).joined()
    }
    public static func chineseNumber(_ n: Int) -> String {
        let a = ["零","一","二","三","四","五","六","七","八","九"]
        if n < 10 { return a[max(0,n)] }
        if n < 20 { return "十" + (n == 10 ? "" : a[n % 10]) }
        return a[n / 10] + "十" + (n % 10 == 0 ? "" : a[n % 10])
    }
    public static func render(_ template: String, date: Date, engine: CalendarEngine, iso: Bool = true) -> String {
        let c = engine.calendar.dateComponents([.year,.month,.day], from: date)
        let l = engine.lunar(date)
        let term = SolarTerms.on(date, engine: engine)?.name ?? ""
        let values: [String: String] = [
            "cnYear":chineseDigits(c.year!), "cnShortYear":chineseDigits(c.year! % 100),
            "cnMonth":chineseNumber(c.month!), "cnDay":chineseNumber(c.day!),
            "weekday":engine.format(date,"EEEE"), "weekShort":engine.format(date,"EEE"),
            "ganzhi":l.yearName, "animal":l.animal, "lunarMonth":l.monthName, "lunarDay":l.dayName, "lunar":l.monthName+l.dayName,
            "branch":engine.traditionalTime(date,detailed:false), "ke":engine.traditionalTime(date), "term":term,
            "zodiac":engine.zodiac(date).name, "dayOfYear":String(engine.progress(date,lunar:false).day), "week":String(engine.week(date,iso:iso).week), "ampm":engine.format(date,"a")
        ]
        var result = template
        for (name, token) in fields {
            _ = name
            result = result.replacingOccurrences(of:"{\(token)}", with: values[token] ?? engine.format(date,token))
        }
        // Optional segments are explicit: [ · {term}] disappears as a whole on non-term days.
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\[\\]]*)\\]") {
            let source = result as NSString
            for match in regex.matches(in:result, range:NSRange(location:0,length:source.length)).reversed() {
                let inner = source.substring(with: match.range(at:1))
                let hasContent = inner.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
                let range = Range(match.range,in:result)!
                result.replaceSubrange(range, with:hasContent ? inner : "")
            }
        }
        return result.replacingOccurrences(of:"\n",with:" ").prefix(160).description
    }
}
