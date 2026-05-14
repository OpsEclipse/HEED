import SwiftUI

struct TerminalWorkspaceView: View {
    let workspace: TerminalShellWorkspace

    private var selectedTerminal: TerminalShellTerminal? {
        workspace.selectedTerminal
            ?? workspace.selectedBranch?.terminals.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            terminalTabBar
            terminalBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .overlay {
            Rectangle()
                .stroke(HeedTheme.ColorToken.borderStrong, lineWidth: HeedTheme.Stroke.brutalist)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-workspace")
    }

    private var terminalTabBar: some View {
        HStack(spacing: 0) {
            ForEach(workspace.selectedBranch?.terminals ?? []) { terminal in
                terminalTabButton(terminal)
            }

            Button { } label: {
                Text("+")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add terminal tab")
            .accessibilityIdentifier("terminal-tab-add")

            Spacer(minLength: 0)
        }
        .frame(height: 42)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(height: HeedTheme.Stroke.brutalist)
        }
    }

    private func terminalTabButton(_ terminal: TerminalShellTerminal) -> some View {
        let isSelected = terminal.id == selectedTerminal?.id
        let title = tabTitle(for: terminal, isSelected: isSelected)

        return Button { } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(isSelected ? Color.white.opacity(0.10) : Color.clear)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(HeedTheme.ColorToken.borderSubtle)
                        .frame(width: HeedTheme.Stroke.brutalist)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityIdentifier("terminal-tab-\(terminal.id)")
    }

    private func tabTitle(for terminal: TerminalShellTerminal, isSelected: Bool) -> String {
        guard isSelected else {
            return terminal.title
        }

        let projectName = workspace.selectedProject?.name ?? "no project"
        let branchName = workspace.selectedBranch?.name ?? "no branch"
        return "\(projectName) / \(branchName) / \(terminal.title)"
    }

    private var terminalBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let selectedTerminal {
                    ForEach(Array(selectedTerminal.promptLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("$") ? HeedTheme.ColorToken.textSecondary : HeedTheme.ColorToken.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("█")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.actionYellow)
                        .accessibilityHidden(true)
                } else {
                    Text("No terminal selected")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .heedHiddenScrollBars()
        .background(HeedTheme.ColorToken.canvas)
    }
}
