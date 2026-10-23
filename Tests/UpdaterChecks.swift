import AppKit
import Sparkle

// Runs only in an isolated test .app with its own defaults domain. Probes the
// real Sparkle engine without installing anything or touching the running app.
@MainActor final class Probe: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var controller: SPUStandardUpdaterController!
    var found = false
    var model: SoftwareUpdater?
    let expected = ProcessInfo.processInfo.arguments.last!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if expected == "model" {
            let model = SoftwareUpdater()
            self.model = model
            model.start()
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {
                guard model.canCheck else { self.finish(false,"manual check is disabled"); return }
                model.setAutomaticChecks(true)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
                    guard model.automaticChecks else { self.finish(false,"UI did not observe toggle on"); return }
                    model.setAutomaticChecks(false)
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.1) {
                        self.finish(!model.automaticChecks,"real settings model observes availability and preferences")
                    }
                }
            }
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        controller.startUpdater()
        let updater = controller.updater
        guard updater.canCheckForUpdates else { finish(false, "updater did not start"); return }
        // Exercise Sparkle-backed preferences in the isolated domain, then leave checks off.
        updater.automaticallyChecksForUpdates = true
        guard updater.automaticallyChecksForUpdates else { finish(false, "toggle on failed"); return }
        updater.automaticallyChecksForUpdates = false
        guard !updater.automaticallyChecksForUpdates else { finish(false, "toggle off failed"); return }
        updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline:.now()+25) { self.finish(false,"timeout") }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found = item.versionString == ProcessInfo.processInfo.environment["EXPECTED_BUILD"]
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let error = error as NSError?
        if let error { print("Sparkle result: \(error.domain) / \(error.code)") }
        switch expected {
        case "available": finish(found && error == nil, "signed new version detected")
        case "current": finish(!found && (error == nil || error?.code == Int(SUError.noUpdateError.rawValue)), "no update")
        case "tampered": finish(!found && error != nil && error?.code != Int(SUError.noUpdateError.rawValue), "altered feed rejected")
        default: finish(false,"unknown test")
        }
    }
    func finish(_ success: Bool, _ message: String) {
        print("\(success ? "PASS" : "FAIL"): \(expected): \(message)")
        if let errorDomain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName:errorDomain) }
        exit(success ? 0 : 1)
    }
}

@main struct UpdaterChecks {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let probe = Probe()
        application.delegate = probe
        withExtendedLifetime(probe) { application.run() }
    }
}
