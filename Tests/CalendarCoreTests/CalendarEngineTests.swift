import Foundation
import CoreGraphics
import CalendarCore


var failures = 0
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { print("FAIL \(file):\(line): \(actual) != \(expected)"); failures += 1 }
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { print("FAIL \(file):\(line): expected true"); failures += 1 } }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { print("FAIL \(file):\(line): expected nil"); failures += 1 } }

final class CalendarEngineTests {
    let e = CalendarEngine()
    func testLunarNewYearAndLeapMonth() {
        let before = e.lunar(e.date(2026,2,16)), after = e.lunar(e.date(2026,2,17))
        XCTAssertEqual(before.yearName,"乙巳"); XCTAssertEqual(before.animal,"蛇")
        XCTAssertEqual(after.yearName,"丙午"); XCTAssertEqual(after.animal,"马")
        XCTAssertEqual(after.month,1); XCTAssertEqual(after.day,1)
        let leap = e.lunar(e.date(2025,7,25))
        XCTAssertTrue(leap.isLeapMonth); XCTAssertEqual(leap.monthName,"闰六月"); XCTAssertEqual(leap.day,1)
        let october = e.lunar(e.date(2026,10,21))
        XCTAssertEqual(october.month,9); XCTAssertEqual(october.day,12)
    }
    func testMonthGridDoesNotDropSixthWeek() {
        let feb = e.monthDays(e.date(2026,2,1))
        XCTAssertEqual(feb.count,35); XCTAssertEqual(e.key(feb.first!),"2026-01-26")
        let march = e.monthDays(e.date(2026,3,1))
        XCTAssertEqual(march.count,42); XCTAssertEqual(e.key(march.last!),"2026-04-05")
        let sunday = e.monthDays(e.date(2026,2,1),mondayFirst:false)
        XCTAssertEqual(sunday.count,28)
    }
    func testZodiacBoundaryAndYearRollover() {
        XCTAssertEqual(e.zodiac(e.date(2026,10,22)).name,"天秤座")
        XCTAssertEqual(e.zodiac(e.date(2026,10,23)).name,"天蝎座")
        XCTAssertEqual(e.zodiac(e.date(2026,10,23)).day,1)
        XCTAssertEqual(e.zodiac(e.date(2026,1,1)).name,"摩羯座")
        XCTAssertEqual(e.zodiac(e.date(2026,1,1)).day,11)
    }
    func testYearProgressBoundaries() {
        let start = e.progress(e.date(2026,1,1,hour:0),lunar:false)
        XCTAssertEqual(start.day,1); XCTAssertEqual(start.fraction,0)
        XCTAssertEqual(e.progress(e.date(2024,12,31),lunar:false).total,366)
        let lunarStart = e.progress(e.date(2026,2,17,hour:0),lunar:true)
        XCTAssertEqual(lunarStart.day,1); XCTAssertEqual(lunarStart.fraction,0)
        XCTAssertEqual(e.progress(e.date(2025,8,1),lunar:true).total,384)
    }
    func testISOWeekUsesWeekYear() {
        XCTAssertEqual(e.week(e.date(2021,1,1),iso:true).year,2020)
        XCTAssertEqual(e.week(e.date(2021,1,1),iso:true).week,53)
        XCTAssertEqual(e.week(e.date(2021,1,1),iso:false).week,1)
    }
    func testTraditionalClockQuarterAndMidnight() {
        XCTAssertEqual(e.traditionalTime(e.date(2026,10,21,hour:15,minute:45)),"申时三刻")
        XCTAssertEqual(e.traditionalTime(e.date(2026,10,21,hour:23)),"子时初刻")
        XCTAssertEqual(e.traditionalTime(e.date(2026,10,21,hour:0)),"子时四刻")
        XCTAssertEqual(e.traditionalTime(e.date(2026,10,21,hour:20,minute:32)),"戌时六刻")
    }
    func testFormatSeparatorsAndChineseAndOptionalFields() {
        let date = e.date(2026,10,21,hour:20,minute:32,second:34)
        XCTAssertEqual(DateFormats.render("{yyyy} 年 {M} 月 {d} 日 {HH}:{mm}:{ss}",date:date,engine:e),"2026 年 10 月 21 日 20:32:34")
        XCTAssertEqual(DateFormats.render("{cnShortYear}.{cnMonth}.{cnDay}",date:date,engine:e),"二六.十.二十一")
        XCTAssertEqual(DateFormats.render("{yyyy}-{MM}-{dd}[ · {term}]",date:date,engine:e),"2026-10-21")
        XCTAssertEqual(DateFormats.render("{yyyy}-{MM}-{dd}[ · {term}]",date:e.date(2026,10,23),engine:e),"2026-10-23 · 霜降")
    }
    func testSolarTermModelAndDayOne() {
        let events = SolarTerms.events(year:2026,engine:e)
        XCTAssertEqual(events.count,24)
        XCTAssertEqual(e.key(events[2].date),"2026-02-04")
        XCTAssertEqual(e.key(events[19].date),"2026-10-23")
        let around = SolarTerms.surrounding(e.date(2026,10,23,hour:0),engine:e)
        XCTAssertEqual(around.current.name,"霜降")
        XCTAssertEqual(e.days(from:around.current.date,to:e.date(2026,10,23)),0)
        XCTAssertEqual(SolarTerms.surrounding(e.date(2026,1,1),engine:e).current.name,"冬至")
    }
    func testHolidayOverridesWeekendsAndUnknownYears() {
        let h = HolidayCalendar(engine:e)
        XCTAssertEqual(h.status(e.date(2026,10,10),engine:e)?.status,.work)
        XCTAssertEqual(h.status(e.date(2026,10,1),engine:e)?.status,.rest)
        XCTAssertEqual(h.workDays(from:e.date(2026,10,1),to:e.date(2026,10,10),engine:e),3)
        XCTAssertNil(h.workDays(from:e.date(2026,12,31),to:e.date(2027,1,2),engine:e))
    }
    func testSettingsPlacementPreservesCalendarAtEitherEdge() {
        let screen = CGRect(x:0,y:0,width:1440,height:875)
        for anchor in [CGRect(x:1370,y:880,width:60,height:24), CGRect(x:30,y:880,width:60,height:24)] {
            let collapsed = WorkspacePlacement(anchor:anchor,visibleFrame:screen,calendarHeight:690,settings:false)
            let expanded = WorkspacePlacement(anchor:anchor,visibleFrame:screen,calendarHeight:690,settings:true)
            XCTAssertTrue(expanded.frame.minX >= screen.minX)
            XCTAssertTrue(expanded.frame.maxX <= screen.maxX)
            let calendarX = expanded.frame.minX + (expanded.settingsOnLeft ? expanded.settingsWidth + 1 : 0)
            XCTAssertEqual(calendarX,collapsed.frame.minX)
            XCTAssertEqual(expanded.frame.maxY,collapsed.frame.maxY)
        }
    }
    func testSettingsPlacementHandlesSmallAndSecondaryScreens() {
        for screen in [CGRect(x:0,y:0,width:1024,height:700), CGRect(x:-1920,y:100,width:1920,height:1055)] {
            let anchor = CGRect(x:screen.maxX-70,y:screen.maxY+4,width:60,height:24)
            let placement = WorkspacePlacement(anchor:anchor,visibleFrame:screen,calendarHeight:900,settings:true)
            XCTAssertTrue(placement.frame.minX >= screen.minX)
            XCTAssertTrue(placement.frame.maxX <= screen.maxX)
            XCTAssertTrue(placement.frame.minY >= screen.minY)
            XCTAssertTrue(placement.frame.maxY <= screen.maxY)
            XCTAssertTrue(placement.settingsWidth >= 320)
            XCTAssertTrue(placement.settingsOnLeft)
        }
    }
    func testHoverSpringCanReverseWithoutResettingVelocity() {
        var spring = HoverSpring(position:.zero)
        spring.target = CGPoint(x:120,y:30)
        for _ in 0..<8 { spring.step(seconds:1.0/120,response:0.28,damping:0.82) }
        let speed = spring.velocity
        let position = spring.position
        spring.target = CGPoint(x:-80,y:70)
        XCTAssertEqual(spring.velocity,speed)
        XCTAssertEqual(spring.position,position)
        for _ in 0..<300 { spring.step(seconds:1.0/120,response:0.28,damping:0.82) }
        XCTAssertTrue(spring.isSettled)
        XCTAssertTrue(abs(spring.position.x + 80) < 0.1)
        XCTAssertTrue(abs(spring.position.y - 70) < 0.1)
    }
    func testHoverSpringIsStableAcrossRefreshRatesAndStalls() {
        var slow = HoverSpring(position:.zero), fast = slow
        slow.target = CGPoint(x:240,y:120); fast.target = slow.target
        for _ in 0..<120 { slow.step(seconds:1.0/60,response:0.28,damping:0.82) }
        for _ in 0..<240 { fast.step(seconds:1.0/120,response:0.28,damping:0.82) }
        XCTAssertTrue(hypot(slow.position.x-fast.position.x,slow.position.y-fast.position.y) < 0.1)
        fast.target = CGPoint(x:-100,y:0)
        fast.step(seconds:3,response:0.28,damping:0.82)
        XCTAssertTrue(fast.position.x.isFinite && fast.velocity.dx.isFinite)
    }
    func testIconSizeCannotExceedDateFont() {
        XCTAssertEqual(CalendarMetrics.iconSize(6),6)
        XCTAssertEqual(CalendarMetrics.iconSize(12.5),12.5)
        XCTAssertEqual(CalendarMetrics.iconSize(100),CalendarMetrics.dateFontSize)
        XCTAssertEqual(CalendarMetrics.iconSize(-10),CalendarMetrics.iconSizeRange.lowerBound)
        XCTAssertEqual(CalendarMetrics.iconSize(.nan),6)
        XCTAssertEqual(CalendarMetrics.iconSize(.infinity),6)
    }
    func testThemeAccentsRemainReadable() {
        XCTAssertEqual(Set(ThemeColors.names).count,12)
        func blend(_ foreground: RGBColor,_ background: RGBColor,_ opacity: Double) -> RGBColor {
            RGBColor(foreground.red*opacity+background.red*(1-opacity),
                     foreground.green*opacity+background.green*(1-opacity),
                     foreground.blue*opacity+background.blue*(1-opacity))
        }
        for name in ThemeColors.names {
            XCTAssertTrue(ThemeColors.selection(name).contrast(with:RGBColor(1,1,1)) >= 4.5)
            XCTAssertTrue(ThemeColors.ink(name,dark:false).contrast(with:RGBColor(0.98,0.98,0.98)) >= 4.5)
            XCTAssertTrue(ThemeColors.ink(name,dark:true).contrast(with:RGBColor(0.12,0.12,0.12)) >= 4.5)
            // The settings card retains 94% neutral backing even at extreme desktops.
            for desktop in [RGBColor(0,0,0),RGBColor(1,1,1)] {
                XCTAssertTrue(ThemeColors.ink(name,dark:false).contrast(with:blend(RGBColor(1,1,1),desktop,0.94)) >= 4.5)
                XCTAssertTrue(ThemeColors.ink(name,dark:true).contrast(with:blend(RGBColor(0.12,0.12,0.12),desktop,0.94)) >= 4.5)
            }
            let selected = ThemeColors.selection(name)
            XCTAssertTrue(blend(RGBColor(1,1,1),selected,0.9).contrast(with:selected) >= 4.5)
            XCTAssertTrue(!ThemeColors.title(name).isEmpty)
        }
    }
    func testMoonPhaseIsBounded() {
        for year in [1901,2000,2026,2100] {
            let m = MoonPhase(date:e.date(year,1,1))
            XCTAssertTrue((0..<1).contains(m.fraction)); XCTAssertTrue((0...1).contains(m.illumination))
        }
    }
}

@main struct CheckRunner { static func main() async {
if let option = CommandLine.arguments.firstIndex(of:"--validate-holidays"), CommandLine.arguments.count > option + 1 {
    do {
        let root = URL(fileURLWithPath:CommandLine.arguments[option+1],isDirectory:true)
        let manifest = try JSONDecoder().decode(HolidayManifest.self,from:Data(contentsOf:root.appendingPathComponent("index.json")))
        for year in manifest.years.keys.sorted() {
            let item = manifest.years[year]!
            let data = try Data(contentsOf:root.appendingPathComponent(item.path))
            XCTAssertEqual(HolidayRepository.sha256(data),item.sha256)
            let entries = try HolidayRepository.decode(data,year:Int(year)!,version:item.version)
            print("Validated application decoder: \(year), \(entries.count) entries")
        }
    } catch { print("Invalid holiday dataset: \(error)"); exit(1) }
    if failures > 0 { exit(1) }
    return
}
if CommandLine.arguments.contains("--live-holidays") {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:directory) }
    let repository = HolidayRepository(directory:directory)
    let requested = CommandLine.arguments.dropFirst().compactMap(Int.init)
    for year in requested.isEmpty ? [2026,2027] : requested {
        let record = await repository.load(year:year)
        print("Live year=\(year) entries=\(record.entries.count) complete=\(record.complete) provider=\(record.provider) status=\(record.outcome)")
    }
    return
}
let checks = CalendarEngineTests()
checks.testLunarNewYearAndLeapMonth(); print("Checked: testLunarNewYearAndLeapMonth")
checks.testMonthGridDoesNotDropSixthWeek(); print("Checked: testMonthGridDoesNotDropSixthWeek")
checks.testZodiacBoundaryAndYearRollover(); print("Checked: testZodiacBoundaryAndYearRollover")
checks.testYearProgressBoundaries(); print("Checked: testYearProgressBoundaries")
checks.testISOWeekUsesWeekYear(); print("Checked: testISOWeekUsesWeekYear")
checks.testTraditionalClockQuarterAndMidnight(); print("Checked: testTraditionalClockQuarterAndMidnight")
checks.testFormatSeparatorsAndChineseAndOptionalFields(); print("Checked: testFormatSeparatorsAndChineseAndOptionalFields")
checks.testSolarTermModelAndDayOne(); print("Checked: testSolarTermModelAndDayOne")
checks.testHolidayOverridesWeekendsAndUnknownYears(); print("Checked: testHolidayOverridesWeekendsAndUnknownYears")
checks.testMoonPhaseIsBounded(); print("Checked: testMoonPhaseIsBounded")
checks.testSettingsPlacementPreservesCalendarAtEitherEdge(); print("Checked: settings preserve calendar position")
checks.testSettingsPlacementHandlesSmallAndSecondaryScreens(); print("Checked: small and secondary screens")
checks.testHoverSpringCanReverseWithoutResettingVelocity(); print("Checked: continuous hover retargeting")
checks.testHoverSpringIsStableAcrossRefreshRatesAndStalls(); print("Checked: hover refresh rates and stalls")
checks.testIconSizeCannotExceedDateFont(); print("Checked: continuous icon range and invalid values")
checks.testThemeAccentsRemainReadable(); print("Checked: accent and selection text contrast")
await checkHolidayRepository()
checkBelowPlacement()
if failures > 0 { print("FAILED: \(failures) assertions"); exit(1) }; print("All 18 check groups passed.")
} }
