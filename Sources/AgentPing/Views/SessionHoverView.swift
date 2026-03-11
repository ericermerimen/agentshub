import SwiftUI
import AgentPingCore

struct SessionHoverView: View {
    let session: Session
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider + Model
            HStack(spacing: 6) {
                Text(modelLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(session.status.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            // Task description
            if let task = session.taskDescription, !task.isEmpty {
                Text(task)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Context bar
            if let pct = session.contextPercent, pct > 0 {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(contextBarColor(pct))
                                .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            // Cost
            if costTrackingEnabled, let cost = session.costUsd, cost > 0 {
                HStack {
                    Text("Cost")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // cwd
            if let cwd = session.cwd, !cwd.isEmpty {
                HStack {
                    Text("Path")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(displayPath(cwd))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var modelLabel: String {
        let parts = [session.provider, session.model].compactMap { $0 }
        return parts.isEmpty ? "Unknown model" : parts.joined(separator: " ")
    }

    private var statusColor: Color {
        switch session.status {
        case .running:    return Color(.systemGreen)
        case .needsInput: return Color(.systemOrange)
        case .idle:       return Color(.systemBlue)
        case .error:      return Color(.systemRed)
        case .done:       return Color(.systemGray)
        case .unavailable: return Color(.systemGray)
        }
    }

    private func contextBarColor(_ pct: Double) -> Color {
        if pct > 0.85 { return Color(.systemRed).opacity(0.8) }
        if pct > 0.65 { return Color(.systemOrange).opacity(0.7) }
        return Color(.systemGreen).opacity(0.5)
    }

    private func displayPath(_ cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}
