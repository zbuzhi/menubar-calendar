import AppKit
import Combine
import SwiftUI
import Sparkle

/// Sparkle owns its schedule and persisted preferences; holiday refreshes stay independent.
@MainActor final class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var status = ""
    var beforeManualCheck: (() -> Void)?
    private var subscriptions = Set<AnyCancellable>()
    private var started = false
    private lazy var controller = SPUStandardUpdaterController(startingUpdater:false, updaterDelegate:self, userDriverDelegate:nil)

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版"
    }
    static let releasesURL = URL(string:"https://github.com/zbuzhi/menubar-calendar/releases")!

    func start() {
        guard !started else { return }
        started = true
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).receive(on:RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }.store(in:&subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on:RunLoop.main)
            .sink { [weak self] in self?.automaticChecks = $0 }.store(in:&subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on:RunLoop.main)
            .sink { [weak self] in self?.lastChecked = $0 }.store(in:&subscriptions)
        controller.startUpdater()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard started else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func check() {
        guard canCheck else { return }
        beforeManualCheck?()
        status = "正在检查软件更新…"
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "发现新版本 \(item.displayVersionString)"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = "当前已是最新版本"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) {
                status = "当前已是最新版本"
            } else if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.installationCanceledError.rawValue) {
                status = "已取消本次更新"
            } else {
                status = "暂时无法完成更新，可稍后重试"
            }
        } else if status == "正在检查软件更新…" {
            status = "检查已结束"
        }
    }
}

struct SoftwareUpdateSettings: View {
    @ObservedObject var updater: SoftwareUpdater
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("当前版本 \(SoftwareUpdater.version)").font(.system(size:12))
                Spacer()
                Button("检查软件更新…") { updater.check() }.disabled(!updater.canCheck)
            }
            Toggle("自动检查软件更新",isOn:Binding(get:{updater.automaticChecks},set:{updater.setAutomaticChecks($0)}))
            Text(updater.status.isEmpty
                 ? (updater.automaticChecks ? "每天检查一次，安装前由你确认" : "自动检查已关闭，仍可手动检查")
                 : updater.status).font(.system(size:11)).foregroundStyle(.secondary)
            if let date = updater.lastChecked {
                Text("上次检查：\(date.formatted(date:.abbreviated,time:.shortened))")
                    .font(.system(size:10)).foregroundStyle(.secondary)
            }
            Link("查看版本记录",destination:SoftwareUpdater.releasesURL).font(.system(size:11))
        }
    }
}
