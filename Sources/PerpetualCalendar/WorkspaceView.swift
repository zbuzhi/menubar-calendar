import SwiftUI

/// A single native panel and a single glass surface, shared by calendar and settings.
struct WorkspaceView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var inheritedScheme
    var body: some View {
        Group {
            if state.settingsPresented && state.settingsDock == .below {
                VStack(spacing:0) {
                    CalendarView(embedded:true,heightOverride:state.calendarViewportHeight ?? state.calendarPanelHeight)
                    Rectangle().fill(.primary.opacity(0.09)).frame(height:1)
                    settings
                }.frame(width:state.settingsWidth)
            } else {
                HStack(spacing:0) {
                    if state.settingsPresented && state.settingsOnLeft { settings; divider }
                    CalendarView(embedded:true,heightOverride:state.calendarViewportHeight ?? state.workspaceHeight)
                    if state.settingsPresented && !state.settingsOnLeft { divider; settings }
                }
            }
        }
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
        .environment(\.colorScheme,state.colorScheme ?? inheritedScheme)
        .tint(state.accent)
        .preferredColorScheme(state.colorScheme)
    }
    private var divider: some View { Rectangle().fill(.primary.opacity(0.09)).frame(width:1,height:state.workspaceHeight - 32) }
    private var settings: some View {
        SettingsView(embedded:true,width:state.settingsWidth,height:state.settingsViewportHeight ?? state.workspaceHeight)
    }
}
