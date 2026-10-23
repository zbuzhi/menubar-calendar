import SwiftUI

// Explicit wrapper alias also supports SDKs that introduce a State macro.
typealias LocalState<Value> = SwiftUI.State<Value>

struct VisualMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct PanelBackground: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    var body: some View {
        ZStack {
            if state.preferences.material == "solid" || reduceTransparency {
                Color(white:scheme == .dark ? 0.075 : 0.98)
            } else if state.preferences.material == "glass" {
                nativeGlass
            } else { VisualMaterial() }
            if state.preferences.material != "solid" && !reduceTransparency {
                (scheme == .dark ? Color.black : Color.white).opacity(state.preferences.material == "glass" ? pow(state.preferences.backing,1.8) * 0.78 : state.preferences.backing * 0.85)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
        // Native Liquid Glass already draws its optical rim. Do not add another border.
        .overlay {
            if state.preferences.material != "glass" || reduceTransparency {
                RoundedRectangle(cornerRadius:22).strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.45),lineWidth:0.6)
            }
        }
    }
    @ViewBuilder private var nativeGlass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in:RoundedRectangle(cornerRadius:22))
        } else { VisualMaterial() }
    }
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View { content.modifier(SettingsCard()) }
}
extension View { func surface() -> some View { modifier(Surface()) } }
