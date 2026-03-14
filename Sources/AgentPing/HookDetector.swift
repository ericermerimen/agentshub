import Foundation
import Combine

final class HookDetector: ObservableObject {
    @Published private(set) var isSessionEndHookMissing: Bool = true

    func check() {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let sessionEnd = hooks["SessionEnd"] as? [[String: Any]] else {
            isSessionEndHookMissing = true
            return
        }
        isSessionEndHookMissing = !sessionEnd.contains { entry in
            // Flat format: {"command": "agentping report ..."}
            if let cmd = entry["command"] as? String, cmd.contains("agentping") {
                return true
            }
            // Nested format: {"hooks": [{"type": "command", "command": "agentping report ..."}]}
            if let nested = entry["hooks"] as? [[String: Any]] {
                return nested.contains { hook in
                    (hook["command"] as? String)?.contains("agentping") == true
                }
            }
            return false
        }
    }
}
