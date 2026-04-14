import SwiftUI

struct SessionSidebarView: View {
    let sessions: [TranscriptSession]
    let selectedSessionID: UUID?
    let activeSessionID: UUID?
    let onSelect: (UUID?) -> Void

    private let drawerWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(sessions) { session in
                            sessionRow(for: session)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .heedHiddenScrollBars()
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(SessionSidebarPalette.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SessionSidebarPalette.edge)
                .frame(width: 1)
        }
        .accessibilityIdentifier("session-sidebar")
    }

    private var emptyState: some View {
        Text("No sessions yet.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SessionSidebarPalette.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionRow(for session: TranscriptSession) -> some View {
        let isSelected = session.id == selectedSessionID
        let isLocked = activeSessionID != nil && activeSessionID != session.id

        return Button {
            onSelect(session.id)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? SessionSidebarPalette.selectionBar : Color.clear)
                    .frame(width: 3, height: 18)

                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? SessionSidebarPalette.primaryText : SessionSidebarPalette.icon)
                    .frame(width: 14)

                Text(session.sidebarTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SessionSidebarPalette.primaryText : SessionSidebarPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isSelected ? SessionSidebarPalette.selectionFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isLocked ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityIdentifier("session-row-\(session.id.uuidString)")
        .accessibilityLabel(session.sidebarTitle)
    }
}

private enum SessionSidebarPalette {
    static let canvas = HeedTheme.ColorToken.panel
    static let edge = HeedTheme.ColorToken.borderSubtle
    static let primaryText = HeedTheme.ColorToken.textPrimary
    static let secondaryText = HeedTheme.ColorToken.textSecondary
    static let icon = HeedTheme.ColorToken.textSecondary
    static let selectionFill = Color.white.opacity(0.08)
    static let selectionBar = HeedTheme.ColorToken.textPrimary.opacity(0.86)
}

private extension TranscriptSession {
    var sidebarTitle: String {
        let leadingText = segments
            .lazy
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let leadingText else {
            return "Untitled session"
        }

        let collapsedWhitespace = leadingText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        if collapsedWhitespace.count <= 54 {
            return collapsedWhitespace
        }

        let endIndex = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: 54)
        return "\(collapsedWhitespace[..<endIndex])..."
    }
}
