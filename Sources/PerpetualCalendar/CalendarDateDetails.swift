import SwiftUI
import CalendarCore

/// Compact date information shared by the calendar and native layout previews.
struct CalendarDateDetails: View {
    @EnvironmentObject var state: AppState
    @LocalState<Bool> private var moonInfo = false

    var body: some View {
        let date = state.selected, p = state.preferences
        VStack(alignment:.leading,spacing:9) {
            Divider()
            HStack(alignment:.center,spacing:8) {
                Text(state.engine.format(date,"M月d日")).font(.system(size:18,weight:.semibold))
                Text(state.engine.format(date,"EEEE")).font(.system(size:13))
                Spacer(minLength:0)
                if p.showMoon { moonButton(date) }
            }
            if p.lunar || p.showYear || p.showGanZhi { metadata(date) }
            if p.showDayProgress {
                Divider()
                seasonalProgress(date)
            }
            if p.showCapsule { annualProgress(date) }
            else if p.showWeek { weekSummary(date) }
            if p.showHolidayCountdown { holidayCountdown(date) }
            if p.showNotes { noteButton(date) }
        }
    }

    private func metadata(_ date: Date) -> some View {
        let p = state.preferences, lunar = state.engine.lunar(date)
        let parts = [p.lunar ? "农历"+lunar.monthName+lunar.dayName : nil,
                     p.showYear ? lunar.yearName+"年 · "+lunar.animal+"年" : nil].compactMap { $0 }
        return ViewThatFits(in:.horizontal) {
            HStack(spacing:8) {
                if !parts.isEmpty { Text(parts.joined(separator:" · ")).fixedSize() }
                Spacer(minLength:0)
                if p.showGanZhi { stems(date).fixedSize() }
            }
            VStack(alignment:.leading,spacing:4) {
                if !parts.isEmpty { Text(parts.joined(separator:" · ")) }
                if p.showGanZhi { stems(date) }
            }
        }.font(.system(size:10))
    }

    private func stems(_ date: Date) -> some View {
        Text(state.engine.stemMonth(date)+" · "+state.engine.stemDay(date))
            .foregroundStyle(.secondary)
            .help("干支月以节气交节时刻换月，日干支按北京时间零点换日")
    }

    private func seasonalProgress(_ date: Date) -> some View {
        let e = state.engine, terms = SolarTerms.surrounding(date,engine:e), zodiac = e.zodiac(date)
        return VStack(alignment:.leading,spacing:5) {
            HStack {
                Text(terms.current.name+" 第\(e.days(from:terms.current.date,to:date)+1)天")
                Spacer(minLength:0)
                Text(zodiac.name+" 第\(zodiac.day)天")
            }.font(.system(size:11))
            Text("距\(terms.next.name)还有\(e.days(from:date,to:terms.next.date))天 · 约\(e.format(terms.next.date,"M月d日 HH:mm"))交节")
                .font(.system(size:10)).foregroundStyle(.secondary)
                .help("节气时刻使用低阶天文模型估算，可能存在分钟级误差")
        }
    }

    private func weekText(_ date: Date) -> String {
        let week = state.engine.week(date,iso:state.preferences.isoWeek)
        return "\(String(week.year))年 · 第\(week.week)周"
    }

    private func weekSummary(_ date: Date) -> some View {
        Text(weekText(date)+" · 公历年第\(state.engine.progress(date,lunar:false).day)天")
            .font(.system(size:10)).foregroundStyle(.secondary)
    }

    private var calendarToggle: some View {
        JellySegments("年度历法",selection:$state.preferences.lunarProgress,
                      options:[("公",false),("农",true)],compact:true).frame(width:54)
    }

    private func annualProgress(_ date: Date) -> some View {
        let p = state.preferences
        let progress = state.engine.progress(date,lunar:p.lunarProgress)
        let title = "\(p.lunarProgress ? "农历" : "公历")年已过 \(String(format:"%.1f",progress.fraction*100))%"
        let days = "第\(progress.day)天 / \(progress.total)天"
        let statistics = (p.showWeek && !p.lunarProgress ? weekText(date)+" · " : "") + days
        return VStack(alignment:.leading,spacing:5) {
            if p.showWeek && p.lunarProgress { weekSummary(date) }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:7) {
                    Text(title).font(.system(size:10)).fixedSize()
                    Spacer(minLength:0)
                    Text(statistics).font(.system(size:9)).foregroundStyle(.secondary).fixedSize()
                    calendarToggle
                }
                VStack(spacing:5) {
                    HStack {
                        Text(title).font(.system(size:10))
                        Spacer(minLength:0)
                        calendarToggle
                    }
                    Text(statistics).font(.system(size:10)).foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule().fill(LinearGradient(colors:[state.accent,state.accent.opacity(0.5),.orange.opacity(0.65)],
                                                  startPoint:.leading,endPoint:.trailing))
                        .frame(width:max(2,geometry.size.width*progress.fraction))
                }
            }.frame(height:3)
        }.padding(.vertical,3)
    }

    private func holidayCountdown(_ date: Date) -> some View {
        let text: String
        if let next = state.holidays.nextBreak(after:date,engine:state.engine) {
            let days = state.engine.days(from:date,to:next.date)
            text = days == 0 ? "今天是\(next.name)假期" : "距\(next.name)还有 \(days) 天"
        } else {
            text = state.holidays.coveredYears.contains(state.engine.calendar.component(.year,from:date))
                ? "本年已无后续假期 · 下一年度调休安排未收录" : "该年份调休安排未收录 · 节日与节气仍可查询"
        }
        return Label(text,systemImage:"calendar.badge.clock").font(.system(size:10))
            .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
    }

    private func noteButton(_ date: Date) -> some View {
        VStack(spacing:4) {
            Divider()
            Button { state.toggleNoteEditor(date) } label: {
                HStack(spacing:8) {
                    Image(systemName:"square.and.pencil").foregroundStyle(state.accent)
                    Text("小记").fontWeight(.medium)
                    Text(state.note.isEmpty ? "添加当天记录" : state.note.replacingOccurrences(of:"\n",with:" "))
                        .lineLimit(1).foregroundStyle(state.note.isEmpty ? .secondary : .primary)
                    Spacer(minLength:0)
                    Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(.secondary)
                }.font(.system(size:12)).padding(.vertical,7).contentShape(Rectangle())
            }.buttonStyle(.plain).help("小记 · 点击打开或关闭 · 仅保存在本机")
        }
    }

    private func moonButton(_ date: Date) -> some View {
        let moon = MoonPhase(date:date)
        return Button { moonInfo.toggle() } label: {
            HStack(spacing:5) {
                MoonDisc(fraction:moon.fraction).frame(width:22,height:22)
                Text(moon.name).font(.system(size:10)).foregroundStyle(.secondary)
            }.fixedSize()
        }.buttonStyle(.plain).popover(isPresented:$moonInfo) {
            VStack(spacing:12) {
                Text("月相小窗").font(.headline)
                MoonDisc(fraction:moon.fraction).frame(width:88,height:88)
                Text(moon.name).font(.title3)
                Text("估算月龄 \(moon.age,specifier:"%.1f") 天 · 照亮 \(moon.illumination*100,specifier:"%.0f")%")
                Text("平均朔望月模型，仅作月相示意，非精密天文预报。").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:300)
        }
    }
}
