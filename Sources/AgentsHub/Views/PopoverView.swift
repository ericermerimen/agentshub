import SwiftUI
import AgentsHubCore

enum SessionTab: String, CaseIterable {
    case running = "Running"
    case history = "History"
}

struct PopoverView: View {
    @ObservedObject var manager: SessionManager
    @State private var selectedTab: SessionTab = .running

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AGENTSHUB")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(manager.activeSessions.count) active")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(SessionTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Session list
            ScrollView {
                LazyVStack(spacing: 0) {
                    let sessions = selectedTab == .running
                        ? manager.activeSessions
                        : manager.historySessions

                    if sessions.isEmpty {
                        Text("No \(selectedTab.rawValue.lowercased()) sessions")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(sessions) { session in
                            SessionRowView(session: session)
                                .onTapGesture {
                                    jumpToWindow(session: session)
                                }

                            if session.id != sessions.last?.id {
                                Divider().padding(.leading, 24)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider()

            // Footer
            VStack(spacing: 4) {
                if manager.unavailableCount > 0 {
                    Button {
                        manager.clearUnavailable()
                    } label: {
                        Text("Clear Unavailable (\(manager.unavailableCount))")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private func jumpToWindow(session: Session) {
        let jumper = WindowJumper()
        _ = jumper.jumpTo(session: session)
    }
}
