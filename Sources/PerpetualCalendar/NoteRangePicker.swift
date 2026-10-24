import SwiftUI
import CalendarCore

struct NoteRangePicker: View {
    @EnvironmentObject private var state: AppState
    @LocalState var scope: NoteDateScope
    @LocalState var anchor: Date
    @LocalState var start: Date
    @LocalState var end: Date
    let apply: (NoteDateScope,Date,Date,Date) -> Void
    private var range: NoteDateRange { NoteDateRange(scope:scope,anchor:anchor,from:start,through:end,engine:state.engine) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                ForEach([(NoteDateScope.day,"今天"),(.week,"本周"),(.month,"本月"),(.all,"全部")],id:\.0) { item in
                    Button(item.1) { apply(item.0,Date(),start,end) }.buttonStyle(.bordered)
                }
            }
            Picker("范围",selection:$scope) {
                Text("日").tag(NoteDateScope.day); Text("周").tag(NoteDateScope.week)
                Text("月").tag(NoteDateScope.month); Text("自定义").tag(NoteDateScope.custom)
                Text("全部").tag(NoteDateScope.all)
            }.pickerStyle(.segmented).labelsHidden()
            if scope == .custom {
                DatePicker("开始",selection:$start,displayedComponents:.date)
                DatePicker("结束",selection:$end,displayedComponents:.date)
            } else if scope != .all {
                HStack {
                    Button { shift(-1) } label: { Image(systemName:"chevron.left") }.help("上一段时间")
                    if scope == .month {
                        Picker("年",selection:component(.year)) {
                            ForEach((state.engine.calendar.component(.year,from:anchor)-10)...(state.engine.calendar.component(.year,from:anchor)+10),id:\.self) { Text(String($0)).tag($0) }
                        }.labelsHidden()
                        Picker("月",selection:component(.month)) { ForEach(1...12,id:\.self) { Text("\($0)月").tag($0) } }.labelsHidden()
                    } else { DatePicker(scope == .week ? "所在周" : "日期",selection:$anchor,displayedComponents:.date) }
                    Button { shift(1) } label: { Image(systemName:"chevron.right") }.help("下一段时间")
                }
            }
            HStack {
                Text(range.start.map { $0 + " — " + (range.end ?? $0) } ?? "全部日期").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer(minLength:4)
                Button("应用") { apply(scope,anchor,start,end) }.buttonStyle(.borderedProminent)
            }
        }.padding(16).frame(width:330).environment(\.timeZone,state.engine.calendar.timeZone)
        .onChange(of:start) { if $0 > end { end = $0 } }
        .onChange(of:end) { if $0 < start { start = $0 } }
    }
    private func component(_ part: Calendar.Component) -> Binding<Int> {
        Binding(get:{ state.engine.calendar.component(part,from:anchor) },set:{ value in
            var components = state.engine.calendar.dateComponents([.year,.month],from:anchor)
            if part == .year { components.year = value } else { components.month = value }
            components.day = 1
            if let value = state.engine.calendar.date(from:components) { anchor = value }
        })
    }
    private func shift(_ delta: Int) {
        let component: Calendar.Component = scope == .month ? .month : scope == .week ? .weekOfYear : .day
        anchor = state.engine.calendar.date(byAdding:component,value:delta,to:anchor) ?? anchor
    }
}
