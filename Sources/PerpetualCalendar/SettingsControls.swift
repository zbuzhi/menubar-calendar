import SwiftUI

/// Explicit colors keep controls legible even when native glass shows a busy desktop.
struct SettingsPalette {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var text: Color { dark ? Color(white:0.95) : Color(white:0.12) }
    var secondary: Color { dark ? Color(white:0.72) : Color(white:0.38) }
    var backing: Color { dark ? Color(white:0.075) : Color(white:0.98) }
    var card: Color { dark ? Color(white:0.12) : .white }
    var track: Color { dark ? Color(white:0.21) : Color(white:0.90) }
    var selection: Color { dark ? Color(white:0.32) : .white }
    var border: Color { dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08) }
}

private struct JellyAnimation {
    static func motion(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(response:0.28,dampingFraction:0.78,blendDuration:0.12) }
}

struct JellySegments<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String,Value)]
    var compact: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Namespace private var pill
    init(_ title: String, selection: Binding<Value>, options: [(String,Value)], compact: Bool = false) {
        self.title = title; _selection = selection; self.options = options; self.compact = compact
    }
    var body: some View {
        let palette = SettingsPalette(scheme)
        HStack(spacing:2) {
            ForEach(options.indices,id:\.self) { index in
                let option = options[index]
                Button { withAnimation(JellyAnimation.motion(reduced)) { selection = option.1 } } label: {
                    Text(option.0).font(.system(size:compact ? 10 : 11,weight:selection == option.1 ? .semibold : .regular))
                        .foregroundStyle(selection == option.1 ? palette.text : palette.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth:.infinity,minHeight:compact ? 21 : 29)
                        .background {
                            if selection == option.1 {
                                RoundedRectangle(cornerRadius:8).fill(palette.selection)
                                    .shadow(color:.black.opacity(scheme == .dark ? 0.16 : 0.08),radius:2,y:1)
                                    .matchedGeometryEffect(id:"selection",in:pill)
                            }
                        }.contentShape(RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain)
                .accessibilityLabel(title+"，"+option.0)
                .accessibilityValue(selection == option.1 ? "已选中" : "未选中")
                .accessibilityAddTraits(selection == option.1 ? .isSelected : [])
            }
        }.padding(compact ? 2 : 3).background(palette.track,in:RoundedRectangle(cornerRadius:11))
            .animation(JellyAnimation.motion(reduced),value:selection)
    }
}

struct JellyToggleStyle: ToggleStyle {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        let palette = SettingsPalette(scheme)
        Button { withAnimation(JellyAnimation.motion(reduced)) { configuration.isOn.toggle() } } label: {
            HStack(spacing:12) {
                configuration.label.font(.system(size:12)).foregroundStyle(palette.text)
                Spacer(minLength:8)
                Capsule().fill(configuration.isOn ? state.selectionColor : palette.track)
                    .frame(width:36,height:22)
                    .overlay(alignment:.leading) {
                        Circle().fill(Color.white).frame(width:18,height:18)
                            .shadow(color:.black.opacity(0.15),radius:1,y:1)
                            .offset(x:configuration.isOn ? 16 : 2)
                    }
            }.padding(.vertical,3).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .animation(JellyAnimation.motion(reduced),value:configuration.isOn)
            .accessibilityValue(configuration.isOn ? "开启" : "关闭")
    }
}

struct JellySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState<Bool> private var dragging = false
    private var fraction: Double { min(1,max(0,(value-range.lowerBound)/(range.upperBound-range.lowerBound))) }
    var body: some View {
        let palette = SettingsPalette(scheme)
        GeometryReader { geometry in
            let span = max(1,geometry.size.width-22)
            ZStack(alignment:.leading) {
                Capsule().fill(palette.track).frame(height:4).padding(.horizontal,11)
                Capsule().fill(state.accent).frame(width:span*fraction+2,height:4).offset(x:11)
                Circle().fill(palette.selection).overlay(Circle().strokeBorder(palette.border,lineWidth:1))
                    .shadow(color:.black.opacity(0.16),radius:2,y:1)
                    .frame(width:22,height:22).scaleEffect(dragging ? 1.13 : 1)
                    .offset(x:span*fraction)
            }.frame(height:28).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { event in
                    dragging = true
                    update(range.lowerBound + min(1,max(0,(event.location.x-11)/span))*(range.upperBound-range.lowerBound))
                }.onEnded { _ in dragging = false })
                .animation(reduced ? nil : .interactiveSpring(response:0.16,dampingFraction:0.87),value:fraction)
                .animation(JellyAnimation.motion(reduced),value:dragging)
        }.frame(height:28)
        .focusable()
        .onMoveCommand { direction in
            let delta = step > 0 ? step : (range.upperBound-range.lowerBound)/100
            if direction == .left || direction == .down { update(value-delta) }
            if direction == .right || direction == .up { update(value+delta) }
        }
        .accessibilityElement(children:.ignore).accessibilityLabel(title)
        .accessibilityValue(String(format:"%.1f",value))
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound-range.lowerBound)/20
            update(value + (direction == .increment ? delta : -delta))
        }
    }
    private func update(_ input: Double) {
        let rounded = step > 0 ? (input/step).rounded()*step : input
        value = min(range.upperBound,max(range.lowerBound,rounded))
    }
}

struct JellyButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let palette = SettingsPalette(scheme)
        configuration.label.font(.system(size:11)).foregroundStyle(palette.text)
            .padding(.horizontal,10).padding(.vertical,7)
            .background(palette.selection,in:RoundedRectangle(cornerRadius:7))
            .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(palette.border,lineWidth:0.5))
            .scaleEffect(configuration.isPressed && !reduced ? 0.96 : 1)
            .animation(JellyAnimation.motion(reduced),value:configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
    }
}

struct SettingsCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = SettingsPalette(scheme)
        content.padding(13).background(palette.card.opacity(0.94),in:RoundedRectangle(cornerRadius:12))
            .foregroundStyle(palette.text)
    }
}
