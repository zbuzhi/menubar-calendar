import SwiftUI
import CalendarCore

enum NoteMoveDestination { case today, tomorrow, custom }
enum NoteNotice {
    case deleted(NoteDeletion)
    case moved(Date,Int)
}

struct NoteMoveDatePicker: View {
    let count: Int
    let initialDate: Date
    let cancel: () -> Void
    let apply: (Date) -> Void
    @EnvironmentObject private var state: AppState
    @State private var chosenDate = Date()
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(count == 1 ? "移动小记" : "移动 \(count) 条小记").font(.headline)
            DatePicker("移到",selection:$chosenDate,displayedComponents:.date)
                .environment(\.timeZone,state.engine.calendar.timeZone)
            Text("正文、标签、完成状态和预计完成时刻都会保留。")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Spacer()
                Button("取消",action:cancel).keyboardShortcut(.cancelAction)
                Button("移动") { apply(chosenDate) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:310).onAppear { chosenDate = initialDate }
            .preferredColorScheme(state.colorScheme)
    }
}
