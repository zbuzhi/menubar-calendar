import SwiftUI
import CalendarCore

struct CalendarView: View {
    var embedded = false
    var heightOverride: CGFloat? = nil
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @LocalState<Bool> private var showJump = false
    @LocalState<Date> private var jump = Date()
    var body: some View {
        VStack(spacing:0) {
            header.padding(.horizontal,18).padding(.top,16).padding(.bottom,10)
            ScrollView {
                VStack(spacing:12) {
                    if state.annual { annual } else {
                        CalendarMonthPager(month:state.month,calendar:state.engine.calendar,reduced:reduceMotion,navigate:{ [displayedMonth = state.month] step in
                            guard !state.annual, state.engine.calendar.isDate(state.month,equalTo:displayedMonth,toGranularity:.month) else { return }
                            state.shift(step)
                        }) {
                            CalendarMonthGrid(month:$0)
                        }
                        CalendarDateDetails()
                    }
                    if state.comparison { comparison }
                }.padding(.horizontal,16).padding(.bottom,12)
            }.scrollIndicators(.hidden)
            Divider().padding(.horizontal,16)
            footer.padding(.horizontal,18).padding(.vertical,11)
        }
        .frame(width:420,height: heightOverride ?? state.calendarPanelHeight)
        .background { if !embedded { PanelBackground() } }
        .overlay(alignment:.bottom) {
            if let message = state.toast {
                Label(message,systemImage:"checkmark.circle.fill").font(.caption).padding(9)
                    .background(.regularMaterial,in:Capsule()).padding(.bottom,55).transition(.opacity)
            }
        }
        .fontWeight(state.usesBoldText ? .bold : nil)
        .tint(state.accent).preferredColorScheme(state.colorScheme)
        .animation(.easeInOut(duration:0.15),value:state.toast)

    }
    private var header: some View {
        HStack(spacing:8) {
            Button { jump = state.month; showJump.toggle() } label: {
                HStack(spacing:4) { Text(state.engine.format(state.month,state.annual ? "yyyy年" : "yyyy年 M月")).font(.system(size:23,weight:.semibold)); Image(systemName:"chevron.down").font(.caption2).foregroundStyle(.secondary) }
            }.buttonStyle(.plain).help("跳到指定日期")
            .popover(isPresented:$showJump) {
                VStack(alignment:.leading,spacing:12) {
                    Text("跳转日期 · 1901—2100").font(.headline)
                    DatePicker("日期",selection:$jump,in:state.engine.date(1901,1,1)...state.engine.date(2100,12,31),displayedComponents:.date)
                    Button("前往") { state.select(jump); state.annual = false; showJump = false }.keyboardShortcut(.return)
                }.padding(20).frame(width:300)
            }
            Spacer(minLength:0)
            Button { state.shift(-1) } label: { Image(systemName:"chevron.left") }.help("上个月 / 年")
            Button("今天") { state.today() }.font(.caption)
            Button { state.shift(1) } label: { Image(systemName:"chevron.right") }.help("下个月 / 年")
            Button { state.annual.toggle() } label: { Image(systemName:state.annual ? "calendar" : "square.grid.3x3") }.help(state.annual ? "返回月历" : "年度缩略图")
        }.buttonStyle(.borderless)
    }
    private var footer: some View {
        HStack(spacing:6) {
            Button("回到今天") { state.today() }.buttonStyle(.plain).foregroundStyle(state.accent).font(.system(size:12))
            Spacer(minLength:0)
            if state.preferences.clock { ClockView().environmentObject(state) }
            Spacer(minLength:0)
            Button { state.comparison.toggle() } label: { Image(systemName:"arrow.left.arrow.right") }.help("日期对比")
            Button { state.pinned.toggle(); state.onPin?() } label: { Image(systemName:state.pinned ? "pin.fill" : "pin") }.help("固定面板")
            Button { state.onSettings?() } label: { Image(systemName:state.settingsPresented ? "gearshape.fill" : "gearshape") }.help("设置")
        }.buttonStyle(.borderless)
    }
    private var comparison: some View {
        let days = abs(state.engine.days(from:state.selected,to:state.comparisonDate))
        let work = state.holidays.workDays(from:state.selected,to:state.comparisonDate,engine:state.engine)
        return VStack(alignment:.leading,spacing:9) {
            HStack { Text("日期对比").font(.headline); Spacer(); Button { state.comparison = false } label: { Image(systemName:"xmark") }.buttonStyle(.plain) }
            Text("起点："+state.engine.key(state.selected)).font(.caption)
            DatePicker("终点",selection:$state.comparisonDate,in:state.engine.date(1901,1,1)...state.engine.date(2100,12,31),displayedComponents:.date)
            Text("相差 \(days) 天 · \(days/7) 周 \(days%7) 天").font(.system(size:13,weight:.medium))
            Text(work.map { "其中 \($0) 个工作日（不含起始日）" } ?? "部分年份调休未收录，无法准确计算工作日") .font(.caption).foregroundStyle(.secondary)
        }.surface()
    }
    private var annual: some View {
        VStack(spacing:12) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:12) {
                ForEach(1...12,id:\.self) { m in miniMonth(m) }
            }
            Text("点击月份进入月历 · 小点表示当天有小记").font(.caption).foregroundStyle(.secondary)
            Button("日期对比") { state.comparison.toggle() }
        }
    }
    private func miniMonth(_ month: Int) -> some View {
        let date = state.engine.date(state.selectedYear,month,1)
        let days = state.engine.monthDays(date,mondayFirst:state.preferences.mondayFirst)
        return Button { state.month = date; state.annual = false } label: {
            VStack(alignment:.leading,spacing:6) {
                Text("\(month)月").font(.system(size:12,weight:.semibold))
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:0),count:7),spacing:4) {
                    ForEach(days,id:\.self) { day in
                        let same = state.engine.calendar.component(.month,from:day) == month
                        Text(same ? String(state.engine.calendar.component(.day,from:day)) : " ")
                            .font(.system(size:7)).foregroundStyle(state.engine.calendar.isDateInToday(day) ? state.accent : state.engine.calendar.isDateInWeekend(day) ? .red.opacity(0.8) : .primary)
                            .frame(maxWidth:.infinity)
                            .overlay(alignment:.bottom) { if same && state.hasNotes(on:state.engine.key(day)) { Circle().fill(state.accent).frame(width:2,height:2).offset(y:3) } }
                    }
                }.frame(height:80,alignment:.top)
            }.padding(8).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain)
    }
}

struct ClockView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState<Bool> private var showCopy = false
    @LocalState<Date> private var openedAt = Date()
    var body: some View {
        TimelineView(.periodic(from:Date(timeIntervalSince1970:floor(Date().timeIntervalSince1970)),by:1)) { context in
            Button { openedAt = Date(); showCopy.toggle() } label: {
                VStack(spacing:2) {
                    RollingClockText(text:state.render(state.preferences.clockTemplate,at:context.date),bold:state.usesBoldText,reduced:reduced).lineLimit(1).minimumScaleFactor(0.65)
                    if state.preferences.traditional != "hidden" {
                        Text(state.engine.traditionalTime(context.date,detailed:state.preferences.traditional == "ke")).font(.system(size:9,weight:state.textWeight())).foregroundStyle(.secondary)
                    }
                }.frame(minWidth:100)
            }.buttonStyle(.plain).help("点击复制当前时间")
            .popover(isPresented:$showCopy,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:6) {
                    Text("复制日期时间").font(.headline).padding(.bottom,4)
                    Text("当前时间 · 点击时取最新秒数").font(.caption).foregroundStyle(.secondary)
                    copyRow("复制当前显示格式",state.preferences.menuTemplate)
                    copyRow("复制默认格式",state.preferences.copyTemplate)
                    Divider().padding(.vertical,4)
                    ForEach(DateFormats.copyDefaults,id:\.self) { template in copyRow(state.render(template,at:openedAt),template) }
                    if !state.preferences.favorites.isEmpty {
                        Divider().padding(.vertical,4)
                        ForEach(state.preferences.favorites) { f in copyRow(f.name+" · "+state.render(f.template,at:openedAt),f.template) }
                    }
                    Divider()
                    Button("管理复制格式…") { showCopy = false; state.openSettings(tab:"formats",target:"copy") }.buttonStyle(.plain).foregroundStyle(state.accent).padding(.vertical,7)
                }.padding(16).frame(width:310).tint(state.accent).preferredColorScheme(state.colorScheme)
            }
        }
    }
    private func copyRow(_ title:String,_ template:String) -> some View {
        Button { state.copy(template); showCopy = false } label: {
            HStack { Text(title).font(.system(size:11)).lineLimit(1).minimumScaleFactor(0.7); Spacer(); Image(systemName:"doc.on.doc").font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal,8).padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:6))
    }
}
/// Animate only changed glyphs; unchanged hours and separators stay still.
struct RollingClockText: View {
    let text: String
    let bold: Bool
    let reduced: Bool
    var body: some View {
        HStack(spacing:0) {
            ForEach(Array(text.enumerated()),id:\.offset) { _, character in
                Text(String(character))
                    .id(character)
                    .transition(reduced ? .identity : .asymmetric(
                        insertion:.offset(y:-8).combined(with:.opacity),
                        removal:.offset(y:8).combined(with:.opacity)))
            }
        }
        .font(.system(size:14,weight:bold ? .bold : .medium,design:.monospaced))
        .frame(height:20).clipped()
        .animation(reduced ? nil : .easeInOut(duration:0.35),value:text)
        .accessibilityElement(children:.ignore).accessibilityLabel(text)
    }
}

struct CopyActions: View {
    @EnvironmentObject var state: AppState
    let date: Date
    var isCurrent = true
    private func copy(_ template: String) { state.copy(template,date:isCurrent ? Date() : date) }
    var body: some View {
        Button("复制当前显示格式") { copy(state.preferences.menuTemplate) }
        Button("复制默认格式") { copy(state.preferences.copyTemplate) }
        Divider()
        ForEach(DateFormats.copyDefaults,id:\.self) { template in Button(state.render(template,at:date)) { copy(template) } }
        if !state.preferences.favorites.isEmpty {
            Divider()
            ForEach(state.preferences.favorites) { f in Button(f.name+" · "+state.render(f.template,at:date)) { copy(f.template) } }
        }
        Divider()
        Button("管理复制格式…") { state.onSettings?() }
    }
}
