import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: SessionViewModel
    var onReconnect: (Session) -> Void

    private struct HistoryEntry: Identifiable {
        let id = UUID()
        let session: Session
        let date: String
        let time: String
        let duration: String
        let iconColor: Color
    }

    private var entries: [HistoryEntry] {
        viewModel.sessions.map { session in
            HistoryEntry(
                session: session,
                date: "—",
                time: "—",
                duration: "—",
                iconColor: KineticColors.primary
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mainContent

            analyticsBar
        }
        .background(KineticColors.surface)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            listHeader

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        tableHeader

                        ForEach(entries) { entry in
                            tableRow(entry)
                        }
                    }
                }
            }

            footerBar
        }
        .frame(maxWidth: .infinity)
    }

    private var listHeader: some View {
        HStack {
            Text("Session History")
                .font(KineticFont.headline.font)
                .foregroundStyle(KineticColors.onSurface)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                Text("All Connections")
                    .font(.system(size: 11))
            }
            .foregroundStyle(KineticColors.onSurfaceVariant)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(KineticColors.surfaceContainerHigh)
            )

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(KineticColors.surfaceDim)
        .overlay(alignment: .bottom) {
            GhostDivider()
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("HOST NAME")
                .frame(minWidth: 200, alignment: .leading)
            Text("ADDRESS")
                .frame(minWidth: 140, alignment: .leading)
            Text("DATE/TIME")
                .frame(minWidth: 140, alignment: .leading)
            Text("DURATION")
                .frame(minWidth: 100, alignment: .leading)
            Text("ACTIONS")
                .frame(minWidth: 180, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(KineticColors.onSurfaceVariant)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(KineticColors.surfaceDim.opacity(0.95))
        .overlay(alignment: .bottom) {
            GhostDivider()
        }
    }

    @ViewBuilder
    private func tableRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 16))
                    .foregroundStyle(entry.iconColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entry.iconColor.opacity(0.1))
                    )
                Text(entry.session.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KineticColors.onSurface)
            }
            .frame(minWidth: 200, alignment: .leading)

            Text(entry.session.host)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(KineticColors.surfaceContainerLow)
                )
                .frame(minWidth: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date)
                    .font(.system(size: 13))
                    .foregroundStyle(KineticColors.onSurface)
                Text(entry.time)
                    .font(.system(size: 11))
                    .foregroundStyle(KineticColors.onSurfaceVariant)
            }
            .frame(minWidth: 140, alignment: .leading)

            Text(entry.duration)
                .font(.system(size: 13))
                .foregroundStyle(KineticColors.onSurfaceVariant)
                .frame(minWidth: 100, alignment: .leading)

            HStack(spacing: 8) {
                KineticButton("View Logs", style: .ghost) {}
                KineticButton("Reconnect", style: .primary) {
                    onReconnect(entry.session)
                }
            }
            .frame(minWidth: 180, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.clear)
        )
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.03).frame(height: 1)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 6) {
                Circle()
                    .fill(KineticColors.primary)
                    .frame(width: 6, height: 6)
                Text("\(entries.count) Total entries")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(KineticColors.onSurfaceVariant)
        .padding(.horizontal, 24)
        .frame(height: 36)
        .background(KineticColors.surfaceContainerLow)
        .overlay(alignment: .top) {
            GhostDivider()
        }
    }

    private var analyticsBar: some View {
        VStack(spacing: 0) {
            GhostDivider()

            HStack(spacing: 32) {
                // Most Frequent Host
                VStack(alignment: .leading, spacing: 4) {
                    Text("MOST FREQUENT HOST")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.2)
                        .foregroundStyle(KineticColors.onSurfaceVariant)

                    if let first = entries.first?.session.name {
                        Text(first)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(KineticColors.onSurface)
                    } else {
                        Text("—")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(KineticColors.onSurfaceVariant)
                    }
                }

                // Total Sessions
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL SESSIONS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.2)
                        .foregroundStyle(KineticColors.onSurfaceVariant)

                    Text("\(entries.count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KineticColors.onSurface)
                }

                Spacer()

                // Encryption badge
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .foregroundStyle(KineticColors.tertiary)
                    Text("End-to-End Encrypted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KineticColors.onSurfaceVariant)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(KineticColors.surfaceContainerHigh.opacity(0.6))
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(KineticColors.surfaceContainerLow)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(KineticColors.outline)
            Text("No session history yet")
                .font(KineticFont.body.font)
                .foregroundStyle(KineticColors.onSurfaceVariant)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
