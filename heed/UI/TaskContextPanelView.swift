import SwiftUI

struct TaskContextPanelView: View {
    let presentation: TaskContextPanelPresentation
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.panelTitle)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)

                    if let taskTitle = presentation.taskTitle {
                        Text(taskTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    }
                }

                Spacer(minLength: 12)

                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .accessibilityIdentifier("task-context-close")
            }

            if let statusText = presentation.statusText {
                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(presentation.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 14))
                                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .heedHiddenScrollBars()
            .scrollIndicators(.hidden)

            HStack(spacing: 12) {
                if let secondaryTitle = presentation.footer.secondaryActionTitle {
                    Button(secondaryTitle, action: onSecondaryAction)
                        .buttonStyle(.plain)
                        .disabled(!presentation.footer.isSecondaryActionEnabled)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
                        .accessibilityIdentifier("task-context-secondary")
                }

                Spacer(minLength: 12)

                Button(presentation.footer.primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(
                        HeedTransportButtonStyle(
                            fillColor: HeedTheme.ColorToken.actionYellow,
                            textColor: Color.black.opacity(0.8),
                            size: .compact
                        )
                    )
                    .disabled(!presentation.footer.isPrimaryActionEnabled)
                    .accessibilityIdentifier("task-context-primary")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderSubtle)
                .frame(width: 1)
        }
    }
}
