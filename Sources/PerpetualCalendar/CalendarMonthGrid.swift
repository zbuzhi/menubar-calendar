import SwiftUI
import CalendarCore

struct CalendarMonthGrid: View {
    let month: Date
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dates = state.engine.monthDays(month,mondayFirst:state.preferences.mondayFirst)
        let weekdays = state.preferences.mondayFirst ? ["一","二","三","四","五","六","日"] : ["日","一","二","三","四","五","六"]
        return VStack(spacing:4) {
            HStack(spacing:0) {
                ForEach(weekdays,id:\.self) { day in Text(day).font(.system(size:11,weight:.medium)).foregroundStyle(day == "六" || day == "日" ? Color.red.opacity(0.8) : .secondary).frame(maxWidth:.infinity) }
            }.padding(.bottom,4)
            ForEach(0..<(dates.count / 7),id:\.self) { row in
                let week = Array(dates[(row*7)..<(row*7+7)])
                let hasIcons = state.preferences.zodiac != "hidden" || (state.preferences.termIcons && week.contains { SolarTerms.on($0,engine:state.engine) != nil })
                HStack(spacing:2) { ForEach(week,id:\.self) { date in dayCell(date,icons:hasIcons) } }
            }
        }
        .coordinateSpace(name:"month-grid")
        .backgroundPreferenceValue(DayCellFrames.self) { frames in
            JellyHoverLayer(frames:Array(frames.values),color:NSColor(state.accent),mode:reduceMotion ? "off" : state.preferences.motion)
                .accessibilityHidden(true)
        }
    }
    private func dayCell(_ date: Date, icons: Bool) -> some View {
        let e = state.engine, p = state.preferences
        let key = e.key(date), selected = e.calendar.isDate(date,inSameDayAs:state.selected)
        let currentMonth = e.calendar.isDate(date,equalTo:month,toGranularity:.month)
        let term = SolarTerms.on(date,engine:e)
        let lunar = e.lunar(date), zodiac = e.zodiac(date)
        let festival = p.festivals ? e.festival(date) : nil
        let holiday = p.holidays ? state.holidays.status(date,engine:e) : nil
        let today = e.calendar.isDateInToday(date)
        return Button { state.select(date) } label: {
            VStack(spacing:3) {
                Text(String(e.calendar.component(.day,from:date)))
                    .font(.system(size:CalendarMetrics.dateFontSize,weight:state.textWeight(selected || today ? .semibold : .medium)))
                    .foregroundStyle(selected ? .white : e.calendar.isDateInWeekend(date) ? Color.red.opacity(0.85) : .primary)
                if p.lunar || festival != nil || term != nil {
                    Text(festival ?? term?.name ?? (p.lunar ? lunar.short : ""))
                        .font(.system(size:9)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? .white.opacity(0.9) : festival != nil || term != nil ? state.accent : .secondary)
                }
                if icons {
                    HStack(spacing:7) {
                        if p.zodiacLeft { zodiacItem(zodiac,selected:selected); termItem(term,selected:selected) }
                        else { termItem(term,selected:selected); zodiacItem(zodiac,selected:selected) }
                    }.frame(height:max(9,state.effectiveIconSize))
                }
            }
            .frame(maxWidth:.infinity).frame(height:state.preferences.compact ? (icons ? 58 : p.lunar ? 43 : 32) : (icons ? 70 : 54))
            .background { if selected { RoundedRectangle(cornerRadius:10).fill(state.selectionColor.gradient) } }
            .overlay { if today && !selected { RoundedRectangle(cornerRadius:10).strokeBorder(state.accent.opacity(0.6),lineWidth:1) } }
            .overlay(alignment:.topTrailing) {
                if let holiday {
                    Text(holiday.status.rawValue).font(.system(size:7,weight:.semibold))
                        .foregroundStyle(selected ? .white : holiday.status == .rest ? Color.red : .orange).padding(2)
                }
            }
            .overlay(alignment:.bottomTrailing) {
                if state.hasNotes(on:key) { Circle().fill(selected ? .white : state.accent).frame(width:3,height:3).padding(4) }
            }
            .opacity(currentMonth ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius:10))
        }.buttonStyle(.plain)
        .background(GeometryReader { geometry in
            Color.clear.preference(key:DayCellFrames.self,value:[key:geometry.frame(in:.named("month-grid"))])
        })
        .help("\(e.format(date,"yyyy年M月d日 EEEE"))\n农历\(lunar.monthName)\(lunar.dayName) · \(zodiac.name)\(term.map { " · \($0.name)" } ?? "")")
        .accessibilityLabel("\(e.format(date,"M月d日"))，农历\(lunar.monthName)\(lunar.dayName)，\(zodiac.name)")
        .contextMenu {
            Button("复制该日期 · \(e.key(date))") { state.copy("{yyyy}-{MM}-{dd}",date:date) }
            Button("复制该日期 · 农历") { state.copy("{ganzhi}年{lunar}",date:date) }
            Button("与另一日期比较") { state.select(date); state.comparisonDate = Date(); state.comparison = true }
            Button("添加 / 编辑当天小记") { state.select(date); state.preferences.showNotes = true; state.noteEditorDate = date }
        }
    }
    @ViewBuilder private func zodiacItem(_ zodiac: Zodiac, selected: Bool) -> some View {
        if state.preferences.zodiac == "icon" {
            ZodiacIcon(index:zodiac.index).frame(width:state.effectiveIconSize,height:state.effectiveIconSize)
                .animation(reduceMotion ? nil : .interactiveSpring(response:0.18,dampingFraction:0.88),value:state.effectiveIconSize)
                .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
        } else if state.preferences.zodiac == "text" {
            Text(zodiac.name).font(.system(size:7)).foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
        }
    }
    @ViewBuilder private func termItem(_ term: SolarTerm?, selected: Bool) -> some View {
        if state.preferences.termIcons, let term {
            Image(systemName:termSymbol(term.index)).font(.system(size:state.effectiveIconSize - 1)).foregroundStyle(selected ? .white : state.accent.opacity(0.8))
                .animation(reduceMotion ? nil : .interactiveSpring(response:0.18,dampingFraction:0.88),value:state.effectiveIconSize)
        }
    }
    private func termSymbol(_ i: Int) -> String { ["snowflake","snowflake","leaf","cloud.rain","bolt","leaf","leaf","cloud.rain","sun.max","leaf","leaf","sun.max","sun.max","sun.max","leaf","sun.haze","drop","leaf","drop","leaf","snowflake","cloud.snow","cloud.snow","moon.stars"][i] }
}
