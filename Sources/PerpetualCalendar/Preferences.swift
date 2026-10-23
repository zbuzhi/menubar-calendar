import Foundation

struct SavedFormat: Codable, Identifiable {
    var id = UUID()
    var name: String
    var template: String
}
struct Preferences: Codable {
    // Optional for compatibility with preferences saved before this option existed.
    var boldText: Bool? = false
    var glassStyle: String? = "clear"
    var glassTint: Double? = 0
    var theme = "system"
    var material = "glass"
    var backing = 0.12
    var seasonal = false
    var accent = "blue"
    var compact = true
    var lunar = true
    var festivals = true
    var holidays = true
    var zodiac = "icon"
    var termIcons = true
    var zodiacLeft = true
    var iconSize = 6.0
    var mondayFirst = true
    var isoWeek = true
    var showYear = true
    var showGanZhi = false
    var showDayProgress = true
    var showWeek = true
    var showCapsule = true
    var lunarProgress = false
    var showMoon = true
    var showNotes = true
    var showHolidayCountdown = true
    var clock = true
    var traditional = "ke"
    var motion = "soft"
    var menuTemplate = "{M}月{d}日 {weekShort} {HH}:{mm}"
    var clockTemplate = "{HH}:{mm}:{ss}"
    var copyTemplate = "{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}"
    var favorites: [SavedFormat] = []
}

