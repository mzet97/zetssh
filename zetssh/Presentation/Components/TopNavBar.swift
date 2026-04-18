import SwiftUI

struct TopNavBar: View {
    @Binding var activeTab: TopNavTab
    @Binding var searchText: String
    var onConnect: () -> Void = {}
    var onAdd: () -> Void = {}
    var onToggleSplit: (() -> Void)? = nil

    @State private var showingAboutSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Tab Navigation
            HStack(spacing: 24) {
                ForEach(TopNavTab.allCases, id: \.self) { tab in
                    tabLink(for: tab)
                }
            }
            .padding(.leading, 20)

            // MARK: - Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(KineticColors.outline)

                TextField("Search servers, keys, or logs…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(KineticFont.caption.font)
                    .foregroundStyle(KineticColors.onSurface)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KineticColors.surfaceContainerHighest.opacity(0.4))
            )
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)

            Spacer()

            // MARK: - Action Buttons
            HStack(spacing: 2) {
                actionButton(icon: "plus", action: onAdd)
                actionButton(icon: "rectangle.split.1x2", action: { onToggleSplit?() })
                actionButton(icon: "info.circle", action: { showingAboutSheet = true })
            }

            // MARK: - Connect CTA
            Button(action: onConnect) {
                Text("Connect")
                    .font(KineticFont.body.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(KineticColors.onPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(KineticColors.primaryGradient)
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.trailing, 16)
        }
        .frame(height: 48)
        .background(
            KineticColors.surfaceDim
                .opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            GhostDivider()
        }
        .sheet(isPresented: $showingAboutSheet) {
            AboutSheetView()
        }
    }

    // MARK: - Tab Link

    @ViewBuilder
    private func tabLink(for tab: TopNavTab) -> some View {
        let isActive = activeTab == tab

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeTab = tab
            }
        } label: {
            VStack(spacing: 0) {
                Text(tab.rawValue)
                    .font(KineticFont.caption.font)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundStyle(isActive ? KineticColors.primary : KineticColors.onSurfaceVariant)

                Rectangle()
                    .fill(isActive ? KineticColors.primary : .clear)
                    .frame(height: 2)
                    .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Button

    private func actionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(KineticColors.outline)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TopNavTab

enum TopNavTab: String, CaseIterable {
    case terminals = "Terminals"
    case keys = "Keys"
    case settings = "Settings"
}
