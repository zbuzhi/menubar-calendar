import SwiftUI
import CalendarCore

struct CalendarView: View {
    var embedded = false
    var heightOverride: CGFloat? = nil
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @LocalState<Bool> private var showJump = false
    @LocalState<Date> private var jump = Date()
    @LocalState<Bool> private var moonInfo = false
    var body: some View {
        VStack(spacing:0) {
            header.padding(.horizontal,18).padding(.top,16).padding(.bottom,10)
            ScrollView {
                VStack(spacing:12) {
                    if state.annual { annual } else { monthGrid; details }
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
        .tint(state.accent).preferredColorScheme(state.colorScheme)
        .animation(.easeInOut(duration:0.15),value:state.toast)
        .popover(isPresented:Binding(get:{state.noteEditorDate != nil},set:{if !$0 { state.noteEditorDate = nil }})) {
            if let date = state.noteEditorDate { NoteEditor(date:date).environmentObject(state) }
        }
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
    private var monthGrid: some View {
        let dates = state.engine.monthDays(state.month,mondayFirst:state.preferences.mondayFirst)
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
        let currentMonth = e.calendar.isDate(date,equalTo:state.month,toGranularity:.month)
        let term = SolarTerms.on(date,engine:e)
        let lunar = e.lunar(date), zodiac = e.zodiac(date)
        let festival = p.festivals ? e.festival(date) : nil
        let holiday = p.holidays ? state.holidays.status(date,engine:e) : nil
        let today = e.calendar.isDateInToday(date)
        return Button { state.select(date) } label: {
            VStack(spacing:3) {
                Text(String(e.calendar.component(.day,from:date)))
                    .font(.system(size:CalendarMetrics.dateFontSize,weight:selected || today ? .semibold : .medium))
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
                if state.notes[key] != nil { Circle().fill(selected ? .white : state.accent).frame(width:3,height:3).padding(4) }
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
    private var details: some View {
        let e = state.engine, date = state.selected, p = state.preferences
        let lunar = e.lunar(date), z = e.zodiac(date)
        let terms = SolarTerms.surrounding(date,engine:e)
        let week = e.week(date,iso:p.isoWeek)
        return VStack(alignment:.leading,spacing:9) {
            Divider()
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Text(e.format(date,"M月d日  EEEE")).font(.system(size:18,weight:.semibold))
                    HStack(spacing:7) {
                        if p.lunar { Text("农历"+lunar.monthName+lunar.dayName).font(.system(size:13)) }
                        if p.showYear { Text(lunar.yearName+"年 · "+lunar.animal+"年").font(.system(size:10)).padding(.horizontal,7).padding(.vertical,3).background(.orange.opacity(0.11),in:Capsule()) }
                    }
                }
                Spacer(minLength:2)
                if p.showMoon { moonButton(date) }
            }
            if p.showGanZhi { Text(e.stemMonth(date)+" · "+e.stemDay(date)).font(.caption).foregroundStyle(.secondary).help("干支月以节气交节时刻换月，日干支按北京时间零点换日") }
            if p.showDayProgress {
                HStack { Text(terms.current.name+"第\(e.days(from:terms.current.date,to:date)+1)天"); Spacer(); Text(z.name+"第\(z.day)天") }.font(.system(size:11)).foregroundStyle(state.accent)
                Text("距\(terms.next.name)还有 \(e.days(from:date,to:terms.next.date)) 天 · 约\(e.format(terms.next.date,"M月d日 HH:mm"))交节")
                    .font(.system(size:10)).foregroundStyle(.secondary).help("节气时刻使用低阶天文模型估算，可能存在分钟级误差")
            }
            if p.showWeek {
                Text("\(String(week.year))年第 \(week.week) 周 · 公历年第 \(e.progress(date,lunar:false).day) 天")
                    .font(.system(size:11)).foregroundStyle(.secondary)
            }
            if p.showCapsule { capsule(date) }
            if p.showHolidayCountdown { holidayCountdown(date) }
            if p.showNotes {
                Button { state.noteEditorDate = date } label: {
                    HStack(spacing:8) {
                        Image(systemName:"square.and.pencil").foregroundStyle(state.accent)
                        Text(state.note.isEmpty ? "添加当天小记" : state.note.replacingOccurrences(of:"\n",with:" "))
                            .lineLimit(1).foregroundStyle(state.note.isEmpty ? .secondary : .primary)
                        Spacer(minLength:0)
                        Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(.secondary)
                    }.font(.system(size:12)).padding(10)
                        .background(.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:9))
                }.buttonStyle(.plain).help("一天一条 · 点击编辑 · 仅保存在本机")
            }
        }
    }
    private func moonButton(_ date: Date) -> some View {
        let moon = MoonPhase(date:date)
        return Button { moonInfo.toggle() } label: {
            HStack(spacing:6) { MoonDisc(fraction:moon.fraction).frame(width:28,height:28); Text(moon.name).font(.system(size:10)).foregroundStyle(.secondary) }
        }.buttonStyle(.plain).popover(isPresented:$moonInfo) {
            VStack(spacing:12) {
                Text("月相小窗").font(.headline)
                MoonDisc(fraction:moon.fraction).frame(width:88,height:88)
                Text(moon.name).font(.title3)
                Text("估算月龄 \(moon.age,specifier:"%.1f") 天 · 照亮 \(moon.illumination*100,specifier:"%.0f")%")
                Text("平均朔望月模型，仅作月相示意，非精密天文预报。") .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:300)
        }
    }
    private func capsule(_ date: Date) -> some View {
        let p = state.engine.progress(date,lunar:state.preferences.lunarProgress)
        return VStack(spacing:5) {
            HStack {
                Text("\(state.preferences.lunarProgress ? "农历" : "公历")年已过 \(p.fraction*100,specifier:"%.1f")%")
                Spacer()
                Text("第\(p.day)天 / \(p.total)天").foregroundStyle(.secondary)
                JellySegments("年度历法",selection:$state.preferences.lunarProgress,options:[("公",false),("农",true)],compact:true).frame(width:62)
            }.font(.system(size:10))
            GeometryReader { g in ZStack(alignment:.leading) {
                Capsule().fill(.primary.opacity(0.07))
                Capsule().fill(LinearGradient(colors:[state.accent,state.accent.opacity(0.5),.orange.opacity(0.65)],startPoint:.leading,endPoint:.trailing)).frame(width:max(2,g.size.width*p.fraction))
            } }.frame(height:4)
        }.padding(.vertical,3)
    }
    @ViewBuilder private func holidayCountdown(_ date: Date) -> some View {
        if let next = state.holidays.nextBreak(after:date,engine:state.engine) {
            Label("\(state.engine.days(from:date,to:next.date) == 0 ? "今天是" : "距")\(next.name)\(state.engine.days(from:date,to:next.date) == 0 ? "假期" : "还有 \(state.engine.days(from:date,to:next.date)) 天")",systemImage:"calendar.badge.clock").font(.system(size:10)).foregroundStyle(.secondary)
        } else { Text(state.holidays.coveredYears.contains(state.engine.calendar.component(.year,from:date)) ? "本年已无后续假期 · 下一年度调休安排未收录" : "该年份调休安排未收录 · 节日与节气仍可查询").font(.system(size:10)).foregroundStyle(.secondary) }
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
                            .overlay(alignment:.bottom) { if same && state.notes[state.engine.key(day)] != nil { Circle().fill(state.accent).frame(width:2,height:2).offset(y:3) } }
                    }
                }.frame(height:80,alignment:.top)
            }.padding(8).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain)
    }
}

struct ClockView: View {
    @EnvironmentObject var state: AppState
    @LocalState<Bool> private var showCopy = false
    @LocalState<Date> private var openedAt = Date()
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) { context in
            Button { openedAt = Date(); showCopy.toggle() } label: {
                VStack(spacing:2) {
                    Text(state.render(state.preferences.clockTemplate,at:context.date)).font(.system(size:14,weight:.medium,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.65)
                    if state.preferences.traditional != "hidden" {
                        Text(state.engine.traditionalTime(context.date,detailed:state.preferences.traditional == "ke")).font(.system(size:8)).foregroundStyle(.secondary)
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
                    Button("管理复制格式…") { showCopy = false; state.onSettings?() }.buttonStyle(.plain).foregroundStyle(state.accent).padding(.vertical,7)
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

/// Capture the date at opening, so navigation never writes a note into another day.
struct NoteEditor: View {
    let date: Date
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.dismiss) private var dismiss
    @LocalState<String> private var draft = ""
    @FocusState private var focused: Bool
    private var scheme: ColorScheme { state.colorScheme ?? inheritedScheme }
    private var palette: SettingsPalette { SettingsPalette(scheme) }
    private var key: String { state.engine.key(date) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(state.engine.format(date,"M月d日 EEEE")).font(.headline)
                Spacer()
                Text("当天小记").font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text:$draft).font(.system(size:13)).focused($focused)
                .scrollContentBackground(.hidden).padding(8).frame(height:125)
                .background(palette.card,in:RoundedRectangle(cornerRadius:9))
            HStack {
                if state.notes[key] != nil {
                    Button("删除",role:.destructive) { state.notes.removeValue(forKey:key); dismiss() }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let text = draft.trimmingCharacters(in:.whitespacesAndNewlines)
                    if text.isEmpty { state.notes.removeValue(forKey:key) } else { state.notes[key] = text }
                    dismiss()
                }.keyboardShortcut(.return,modifiers:.command).buttonStyle(.borderedProminent)
            }.controlSize(.small)
        }.padding(18).frame(width:330)
            .foregroundStyle(palette.text).background(palette.backing)
            .environment(\.colorScheme,scheme).tint(state.accent)
            .onAppear { draft = state.notes[key] ?? ""; focused = true }
            .preferredColorScheme(state.colorScheme)
    }
}
