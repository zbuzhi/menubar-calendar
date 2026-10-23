import SwiftUI
import CalendarCore
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var inheritedScheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState<String> private var tab = "appearance"
    @LocalState<Bool> private var moreDetails = false
    @LocalState<Bool> private var moreRules = false
    @LocalState<Bool> private var dataInfo = false
    @Namespace private var accentSelection
    var embedded: Bool
    var panelWidth: CGFloat
    var panelHeight: CGFloat
    init(initialTab: String = "appearance", embedded: Bool = false, width: CGFloat = 620, height: CGFloat = 690) {
        _tab = LocalState(wrappedValue:initialTab)
        self.embedded = embedded; panelWidth = width; panelHeight = height
    }
    private var scheme: ColorScheme { state.colorScheme ?? inheritedScheme }
    private var palette: SettingsPalette { SettingsPalette(scheme) }
    private var motion: Animation? { reduced ? nil : .spring(response:0.28,dampingFraction:0.82) }
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("设置").font(.system(size:17,weight:.semibold))
                Spacer()
                Text("即时预览").font(.system(size:10)).foregroundStyle(palette.secondary)
                if embedded {
                    Button { withAnimation(motion) { state.settingsPresented = false } } label: {
                        Image(systemName:"xmark").font(.system(size:11,weight:.medium)).frame(width:24,height:24)
                    }.buttonStyle(.plain).help("收起设置")
                }
            }.padding(.horizontal,18).padding(.top,17).padding(.bottom,12)
            JellySegments("设置分类",selection:$tab,options:[("外观","appearance"),("日历","calendar"),("格式","formats"),("通用","general"),("更新","updates")])
                .padding(.horizontal,16).padding(.bottom,10)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    switch tab {
                    case "appearance": appearance
                    case "calendar": calendar
                    case "formats": FormatEditor()
                    case "updates": updates
                    default: general
                    }
                }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                    .id(tab).transition(.opacity)
            }.scrollIndicators(.hidden)
        }.frame(width:panelWidth,height:panelHeight)
        .background {
            if !embedded { PanelBackground() }
            palette.backing.opacity(0.94)
        }
        .foregroundStyle(palette.text)
        .environment(\.colorScheme,scheme)
        .toggleStyle(JellyToggleStyle())
        .buttonStyle(JellyButtonStyle())
        .controlSize(.small)
        .tint(state.accent).preferredColorScheme(state.colorScheme)
        .animation(motion,value:tab)
    }
    private func section<Content:View>(_ title:String,@ViewBuilder content:() -> Content) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(palette.secondary)
            content()
        }.frame(maxWidth:.infinity,alignment:.leading).modifier(SettingsCard())
    }
    private var appearance: some View {
        Group {
            section("颜色") {
                JellySegments("颜色模式",selection:$state.preferences.theme,options:[("跟随系统","system"),("浅色","light"),("深色","dark")])
                HStack {
                    Text("主题色").font(.system(size:12)); Spacer()
                    Text(state.preferences.seasonal ? "随当前节气" : ThemeColors.title(state.preferences.accent))
                        .font(.system(size:11)).foregroundStyle(palette.secondary)
                }
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:6),spacing:9) {
                    ForEach(ThemeColors.names,id:\.self) { key in
                        let rgb = ThemeColors.selection(key)
                        let color = Color(.sRGB,red:rgb.red,green:rgb.green,blue:rgb.blue,opacity:1)
                        Button { withAnimation(motion) { state.preferences.accent = key } } label: {
                            VStack(spacing:5) {
                              Circle().fill(color).frame(width:22,height:22)
                                .overlay { if state.preferences.accent == key { Image(systemName:"checkmark").font(.system(size:9,weight:.bold)).foregroundStyle(.white) } }
                                .padding(3).overlay { if state.preferences.accent == key { Circle().strokeBorder(palette.text.opacity(0.5),lineWidth:1).matchedGeometryEffect(id:"accent",in:accentSelection) } }
                              Text(ThemeColors.title(key)).font(.system(size:10)).foregroundStyle(palette.text)
                            }.frame(maxWidth:.infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(state.preferences.seasonal)
                            .opacity(state.preferences.seasonal ? 0.4 : 1)
                            .help(ThemeColors.title(key))
                            .accessibilityLabel("主题色，"+ThemeColors.title(key))
                            .accessibilityValue(state.preferences.accent == key ? "已选中" : "未选中")
                    }
                }
                Toggle("随节气变换颜色",isOn:$state.preferences.seasonal)
            }
            section("背景") {
                JellySegments("背景材质",selection:$state.preferences.material,options:[("液态玻璃","glass"),("磨砂","frosted"),("纯色","solid")])
                if state.preferences.material != "solid" {
                    VStack(spacing:4) {
                        HStack { Text("通透度"); Spacer(); Text("通透 ← → 清晰").foregroundStyle(palette.secondary) }.font(.system(size:11))
                        JellySlider(title:"背景清晰度",value:$state.preferences.backing,range:0...1)
                    }.transition(.opacity)
                }
            }
            section("布局与动效") {
                labeled("显示密度") { JellySegments("显示密度",selection:$state.preferences.compact,options:[("紧凑",true),("舒适",false)]) }
                labeled("悬停动效") { JellySegments("悬停动效",selection:$state.preferences.motion,options:[("关闭","off"),("轻柔","soft"),("果冻","jelly")]) }
            }
        }
    }
    private var calendar: some View {
        Group {
            section("日期图标") {
                JellySegments("星座显示",selection:$state.preferences.zodiac,options:[("隐藏星座","hidden"),("图标","icon"),("小字","text")])
                Toggle("显示节气图标",isOn:$state.preferences.termIcons)
                VStack(spacing:5) {
                    HStack(spacing:10) {
                        Text("图标大小").font(.system(size:12))
                        Spacer()
                        ZodiacIcon(index:9).frame(width:state.effectiveIconSize,height:state.effectiveIconSize)
                        Image(systemName:"leaf").font(.system(size:state.effectiveIconSize))
                        Text(String(format:"%.1f pt",state.effectiveIconSize)).font(.system(size:10,design:.monospaced)).foregroundStyle(palette.secondary).frame(width:46,alignment:.trailing)
                    }
                    JellySlider(title:"图标大小",value:Binding(get:{state.effectiveIconSize},set:{state.preferences.iconSize = CalendarMetrics.iconSize($0)}),range:CalendarMetrics.iconSizeRange,step:0.5)
                    HStack { Text("更小"); Spacer(); Text("最大与日期字号一致") }.font(.system(size:10)).foregroundStyle(palette.secondary)
                }
                JellySegments("图标顺序",selection:$state.preferences.zodiacLeft,options:[("星座在左",true),("节气在左",false)])
            }
            section("月历") {
                Toggle("农历",isOn:$state.preferences.lunar)
                Toggle("节日名称",isOn:$state.preferences.festivals)
                Toggle("放假与补班",isOn:$state.preferences.holidays)
                labeled("一周开始于") { JellySegments("一周开始于",selection:$state.preferences.mondayFirst,options:[("周一",true),("周日",false)]) }
            }
            section("日期详情") {
                Toggle("干支年份与生肖",isOn:$state.preferences.showYear)
                Toggle("节气与星座进度",isOn:$state.preferences.showDayProgress)
                Toggle("年度进度",isOn:$state.preferences.showCapsule)
                Toggle("月相",isOn:$state.preferences.showMoon)
                DisclosureGroup("更多显示内容",isExpanded:$moreDetails) {
                    VStack(spacing:10) {
                        Toggle("干支月日",isOn:$state.preferences.showGanZhi)
                        Toggle("周数与年内天数",isOn:$state.preferences.showWeek)
                        Toggle("假期倒计时",isOn:$state.preferences.showHolidayCountdown)
                        Toggle("当天小记",isOn:$state.preferences.showNotes)
                    }.padding(.top,10)
                }.font(.system(size:11)).animation(motion,value:moreDetails)
            }
            section("底部时钟") {
                Toggle("显示实时时钟",isOn:$state.preferences.clock)
                if state.preferences.clock {
                    JellySegments("传统时间",selection:$state.preferences.traditional,options:[("隐藏时辰","hidden"),("时辰","branch"),("时辰与刻","ke")])
                }
            }
            DisclosureGroup("历法与周数规则",isExpanded:$moreRules) {
                VStack(alignment:.leading,spacing:10) {
                    JellySegments("周数规则",selection:$state.preferences.isoWeek,options:[("ISO 周数",true),("元旦为首周",false)])
                    Text("农历干支年以正月初一换年，干支月按节令换月。时辰采用一刻十五分钟。星座为固定日期分界；月相和交节时刻为近似计算。")
                        .font(.system(size:10)).foregroundStyle(palette.secondary)
                }.padding(.top,10)
            }.font(.system(size:11)).modifier(SettingsCard()).animation(motion,value:moreRules)
        }
    }
    private var general: some View {
        Group {
            section("启动") {
                Toggle("登录时自动启动",isOn:Binding(get:{state.loginEnabled},set:{state.setLogin($0)}))
                if let error = state.loginError { Text(error).font(.caption).foregroundStyle(palette.text) }
                HStack { Text("展开 / 收起"); Spacer(); Text("⌃⌥空格").foregroundStyle(palette.secondary) }.font(.system(size:12))
            }
            section("当天小记") {
                HStack { Text("已保存 \(state.notes.count) 天").font(.system(size:12)); Spacer(); Button("导出备份…") { state.exportNotes() } }
            }
            DisclosureGroup("历法、假期与数据说明",isExpanded:$dataInfo) {
                VStack(alignment:.leading,spacing:10) {
                    Text("支持 1901—2100 年；日期与时钟统一使用北京时间。设置和小记只保存在本机。")
                    Text("内置 2026 年调休；从自维护 GitHub 仓库更新，每 7 天检查索引，仅下载有变化的年度文件。数据按国务院通知人工整理，非官方服务，以官方最新公告为准。不上传设置或小记。")
                    Link("节假日数据仓库",destination:HolidayRepository.sourceURL)
                    Link("数据许可（MIT）",destination:HolidayRepository.sourceURL.appendingPathComponent("blob/main/LICENSE"))
                    Link("官方放假安排",destination:URL(string:HolidayCalendar.source)!)
                    Text("节气采用太阳视黄经近似模型，月相采用平均朔望月模型，均不作为精密天文预报。")
                    Text("先将应用放在固定位置，再开启登录自启。")
                }.font(.system(size:11)).foregroundStyle(palette.secondary).padding(.top,10)
            }.font(.system(size:11)).modifier(SettingsCard()).animation(motion,value:dataInfo)
            HStack { Text("日历 \(SoftwareUpdater.version)").font(.system(size:10)).foregroundStyle(palette.secondary); Spacer(); Button("退出") { NSApp.terminate(nil) } }.padding(.top,5)
        }
    }
    private var updates: some View {
        Group {
            section("软件更新") {
                SoftwareUpdateSettings(updater:state.softwareUpdater)
            }
            section("节假日数据更新") {
                Text(state.holidayStatus).font(.system(size:11)).foregroundStyle(palette.secondary)
                Text("每 7 天检查索引，仅下载有变化的年度数据。不会改变软件版本。")
                    .font(.system(size:11)).foregroundStyle(palette.secondary).fixedSize(horizontal:false,vertical:true)
                Button(state.holidayUpdating ? "检查中…" : "更新假期数据") { state.refreshHolidays(force:true) }.disabled(state.holidayUpdating)
            }
        }
    }
    private func labeled<Content:View>(_ title:String,@ViewBuilder content:() -> Content) -> some View {
        HStack(spacing:16) { Text(title).font(.system(size:12)).frame(width:76,alignment:.leading); content() }
    }
}

struct FormatPart: Identifiable { let id: UUID; var value: String; init(_ value:String) { self.id = UUID(); self.value = value } }
struct FormatEditor: View {
    @EnvironmentObject var state: AppState
    @LocalState<String> private var target = "menu"
    @LocalState<[FormatPart]> private var parts = []
    @LocalState<UUID?> private var dragged = nil
    @LocalState<String> private var presetName = ""
    @LocalState<String> private var literal = ""
    @LocalState<UUID?> private var editingID = nil
    @LocalState<String> private var editValue = ""
    private var template: Binding<String> {
        Binding(get:{ target == "menu" ? state.preferences.menuTemplate : target == "clock" ? state.preferences.clockTemplate : state.preferences.copyTemplate },set:{ value in
            if target == "menu" { state.preferences.menuTemplate = value }
            else if target == "clock" { state.preferences.clockTemplate = value }
            else { state.preferences.copyTemplate = value }
        })
    }
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState<Bool> private var customExpanded = false
    @Namespace private var presetSelection
    @LocalState<Bool> private var templateExpanded = false
    @LocalState<Bool> private var favoritesExpanded = false
    private var motion: Animation? { reduced ? nil : .spring(response:0.28,dampingFraction:0.82) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            JellySegments("编辑位置",selection:$target,options:[("菜单栏","menu"),("底部时钟","clock"),("复制格式","copy")])
                .onChange(of:target) { _ in reload() }
            livePreview
            presetGrid
            DisclosureGroup("自定义组合",isExpanded:$customExpanded) {
                VStack(alignment:.leading,spacing:12) {
                    tokenEditor
                    DisclosureGroup("直接编辑模板",isExpanded:$templateExpanded) { templateEditor }
                        .font(.system(size:11))
                }.padding(.top,12)
            }.font(.system(size:12)).animation(motion,value:customExpanded).animation(motion,value:templateExpanded)
            DisclosureGroup("个人预设与复制收藏",isExpanded:$favoritesExpanded) { favoritesEditor.padding(.top,10) }
                .font(.system(size:12)).animation(motion,value:favoritesExpanded)
        }.onAppear { reload() }
    }
    private var livePreview: some View {
            TimelineView(.periodic(from:.now,by:1)) { context in
                VStack(alignment:.leading,spacing:7) {
                    Text("实时预览 · 北京时间").font(.caption).foregroundStyle(.secondary)
                    Text(state.render(template.wrappedValue,at:context.date)).font(.system(size:20,weight:.semibold,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,minHeight:32)
                }.modifier(SettingsCard())
            }
    }
    private var tokenEditor: some View {
            VStack(alignment:.leading,spacing:12) {
                Text("拖动排序，点击编辑").font(.system(size:11,weight:.medium))
                
                LazyVGrid(columns:[GridItem(.adaptive(minimum:65),spacing:5)],spacing:6) {
                    ForEach(parts) { part in
                        Button { editingID = part.id; editValue = part.value } label: {
                            Text(label(part.value)).font(.system(size:11)).padding(7).frame(maxWidth:.infinity)
                                .background(part.value.hasPrefix("{") ? state.accent.opacity(0.13) : .primary.opacity(0.06),in:RoundedRectangle(cornerRadius:6))
                        }.buttonStyle(.plain)
                        .onDrag { dragged = part.id; return NSItemProvider(object:part.id.uuidString as NSString) }
                        .onDrop(of:[UTType.text],delegate:PartDrop(item:part.id,parts:$parts,dragged:$dragged,onChange:sync,animation:motion))
                        .contextMenu { Button("删除") { parts.removeAll { $0.id == part.id }; sync() } }
                        .popover(isPresented:Binding(get:{editingID == part.id},set:{if !$0 { editingID = nil }})) {
                            VStack(alignment:.leading,spacing:12) {
                                Text("编辑字段或连接符").font(.headline)
                                TextField("内容",text:$editValue).textFieldStyle(.roundedBorder)
                                Menu("替换为日期字段") { ForEach(DateFormats.fields,id:\.1) { name, token in Button(name) { editValue = "{\(token)}" } } }
                                HStack { Button("删除") { parts.removeAll { $0.id == part.id }; sync(); editingID = nil }; Spacer(); Button("完成") { if let i = parts.firstIndex(where:{$0.id == part.id}) { parts[i].value = editValue }; sync(); editingID = nil } }
                            }.padding(16).frame(width:270)
                        }
                    }
                }
                Menu { ForEach(DateFormats.fields,id:\.1) { name, token in Button(name) { parts.append(FormatPart("{\(token)}")); sync() } } } label: { Label("添加字段",systemImage:"plus") }
                HStack(spacing:5) { ForEach([".","-","/","·"," ","年","月","日",":","｜"],id:\.self) { value in Button(value == " " ? "空格" : value) { parts.append(FormatPart(value)); sync() }.font(.caption) } }
                HStack { TextField("自定义连接符或文字",text:$literal).textFieldStyle(.roundedBorder); Button("添加") { guard !literal.isEmpty else { return }; parts.append(FormatPart(literal)); literal = ""; sync() } }
            }
    }
    private var templateEditor: some View {
            VStack(alignment:.leading,spacing:9) {
                
                TextField("例如 {yyyy}-{MM}-{dd}",text:template).textFieldStyle(.roundedBorder).font(.system(size:11,design:.monospaced)).onSubmit { reload() }
                Button("应用到标签编辑器") { reload() }.font(.caption)
                Text("字段使用 {花括号}，其他字符原样输出。可选内容写成 [ · {term}]，没有节气时整段隐藏。数字是否补零、汉字年份、农历与时辰都通过字段选择。") .font(.caption).foregroundStyle(.secondary)
                if invalidTokens { Text("存在未知字段，请检查花括号中的名称。") .font(.caption).foregroundStyle(.orange) }
            }
    }
    private var presetGrid: some View {
            VStack(alignment:.leading,spacing:10) {
                Text("常用样式").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:8) {
                    ForEach(DateFormats.presets,id:\.0) { name, value in Button { template.wrappedValue = value; reload() } label: { VStack(alignment:.leading,spacing:3) { Text(name).font(.caption); Text(state.render(value,at:Date())).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth:.infinity,alignment:.leading).padding(7).background { if template.wrappedValue == value { RoundedRectangle(cornerRadius:6).fill(state.accent.opacity(0.14)).matchedGeometryEffect(id:"preset",in:presetSelection) } else { RoundedRectangle(cornerRadius:6).fill(.primary.opacity(0.035)) } } }.buttonStyle(.plain) }
                }
            }.modifier(SettingsCard()).animation(motion,value:template.wrappedValue)
    }
    private var favoritesEditor: some View {
            VStack(alignment:.leading,spacing:10) {
                
                HStack { TextField("预设名称",text:$presetName).textFieldStyle(.roundedBorder); Button("保存") {
                    guard !presetName.trimmingCharacters(in:.whitespaces).isEmpty else { return }
                    state.preferences.favorites.append(SavedFormat(name:presetName,template:template.wrappedValue)); presetName = ""
                }.disabled(presetName.trimmingCharacters(in:.whitespaces).isEmpty) }
                ForEach(Array(state.preferences.favorites.enumerated()),id:\.element.id) { index, f in
                    HStack {
                        Button(f.name) { template.wrappedValue = f.template; reload() }
                        Spacer()
                        Button { state.copy(f.template) } label: { Image(systemName:"doc.on.doc") }.help("复制当前时间")
                        Button { if index > 0 { state.preferences.favorites.swapAt(index,index-1) } } label: { Image(systemName:"arrow.up") }.disabled(index == 0)
                        Button { state.preferences.favorites.removeAll { $0.id == f.id } } label: { Image(systemName:"trash") }.help("移除预设")
                    }.font(.caption)
                }
            }
    }
    private var invalidTokens: Bool {
        let known = Set(DateFormats.fields.map { "{\($0.1)}" })
        return tokenize(template.wrappedValue).contains { $0.hasPrefix("{") && !known.contains($0) }
    }
    private func label(_ value:String) -> String { if value == " " { return "空格" }; return DateFormats.fields.first { "{\($0.1)}" == value }?.0 ?? value }
    private func tokenize(_ value:String) -> [String] {
        let regex = try! NSRegularExpression(pattern:"\\{[^}]*\\}|[^{}]")
        let ns = value as NSString
        return regex.matches(in:value,range:NSRange(location:0,length:ns.length)).map { ns.substring(with:$0.range) }
    }
    private func reload() { parts = tokenize(template.wrappedValue).map(FormatPart.init) }
    private func sync() { template.wrappedValue = parts.map(\.value).joined() }
}
struct PartDrop: DropDelegate {
    let item: UUID
    @Binding var parts:[FormatPart]
    @Binding var dragged:UUID?
    let onChange:() -> Void
    var animation: Animation? = .spring(response:0.24,dampingFraction:0.82)
    func dropEntered(info:DropInfo) {
        guard let dragged, dragged != item, let from = parts.firstIndex(where:{$0.id == dragged}), let to = parts.firstIndex(where:{$0.id == item}) else { return }
        withAnimation(animation) { parts.move(fromOffsets:IndexSet(integer:from),toOffset:to > from ? to+1 : to) }; onChange()
    }
    func dropUpdated(info:DropInfo) -> DropProposal? { DropProposal(operation:.move) }
    func performDrop(info:DropInfo) -> Bool { dragged = nil; onChange(); return true }
}
