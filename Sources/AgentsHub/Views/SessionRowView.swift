import SwiftUI
import AgentsHubCore

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name ?? "Unnamed Session")
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("→ \(session.app?.uppercased() ?? "UNKNOWN")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if let file = session.file {
                        Text(file)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if session.status == .needsInput {
                Text("INPUT")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: RoundedRectangle(cornerRadius: 3))
            } else {
                Text(elapsedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .primary
        case .needsInput: return .red
        case .idle: return .secondary
        case .done: return .green
        case .error: return .orange
        case .unavailable: return .gray
        }
    }

    private var elapsedTime: String {
        let interval = Date().timeIntervalSince(session.startedAt)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
