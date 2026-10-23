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
    @Published private(set) var checking = false
    @Published private(set) var availableVersion: String?
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
        guard canCheck, !controller.updater.sessionInProgress, !checking else { return }
        availableVersion = nil
        checking = true
        status = "正在检查软件更新…"
        // Probe through Sparkle without presenting its modal checking/result UI.
        controller.updater.checkForUpdateInformation()
    }

    func installUpdate() {
        guard canCheck, !checking, availableVersion != nil else { return }
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        status = "发现新版本 \(item.displayVersionString)"
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        status = "当前已是最新版本"
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        checking = false
        if let error = error as NSError? {
            availableVersion = nil
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
                Button(updater.checking ? "检查中…" : "检查更新") { updater.check() }.disabled(!updater.canCheck || updater.checking)
            }
            Toggle("自动检查软件更新",isOn:Binding(get:{updater.automaticChecks},set:{updater.setAutomaticChecks($0)}))
            HStack(spacing:8) {
                if updater.checking { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width:16,height:16) }
                Text(updater.status.isEmpty
                 ? (updater.automaticChecks ? "每天检查一次，安装前由你确认" : "自动检查已关闭，仍可手动检查")
                 : updater.status).font(.system(size:11)).foregroundStyle(.secondary)
            }.frame(minHeight:20,alignment:.leading).accessibilityElement(children:.combine)
            if let version = updater.availableVersion, !updater.checking {
                Button("查看并安装 \(version)…") { updater.installUpdate() }.disabled(!updater.canCheck)
            }
            if let date = updater.lastChecked {
                Text("上次检查：\(date.formatted(date:.abbreviated,time:.shortened))")
                    .font(.system(size:10)).foregroundStyle(.secondary)
            }
            Link("查看版本记录",destination:SoftwareUpdater.releasesURL).font(.system(size:11))
        }
    }
}
