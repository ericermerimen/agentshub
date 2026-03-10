import SwiftUI
import AgentsHubCore
import Combine

@main
struct AgentsHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusItemController?
    let manager = SessionManager()
    var watcher: DirectoryWatcher?
    var scanTimer: Timer?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApplication.shared.setActivationPolicy(.accessory)

        // Set up menu bar controller
        controller = StatusItemController(manager: manager)

        // Set up directory watcher for live updates
        watcher = DirectoryWatcher { [weak self] in
            self?.manager.reload()
        }
        watcher?.start()

        // Set up notifications
        NotificationManager.shared.setup { [weak self] sessionId in
            guard let session = self?.manager.sessions.first(where: { $0.id == sessionId }) else { return }
            let jumper = WindowJumper()
            _ = jumper.jumpTo(session: session)
        }

        // Watch for sessions that transition to needs-input
        manager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.checkForNeedsInput(sessions: sessions)
            }
            .store(in: &cancellables)

        // Initial load
        manager.reload()

        // Start periodic scan
        startPeriodicScan()
    }

    private var previousNeedsInputIds = Set<String>()

    private func checkForNeedsInput(sessions: [Session]) {
        let currentNeedsInput = Set(sessions.filter { $0.status == .needsInput }.map(\.id))
        let newNeedsInput = currentNeedsInput.subtracting(previousNeedsInputIds)

        for sessionId in newNeedsInput {
            if let session = sessions.first(where: { $0.id == sessionId }) {
                NotificationManager.shared.sendNeedsInput(session: session)
            }
        }

        previousNeedsInputIds = currentNeedsInput
    }

    private func startPeriodicScan() {
        let interval = UserDefaults.standard.double(forKey: "scanInterval")
        let scanInterval = interval > 0 ? interval : 10.0

        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.manager.reload()
        }
    }
}
