import SwiftUI

@main
struct AgentsHubApp: App {
    var body: some Scene {
        MenuBarExtra("AgentsHub", systemImage: "circle.grid.2x2") {
            Text("AgentsHub running")
        }
        Settings {
            Text("Preferences")
        }
    }
}
