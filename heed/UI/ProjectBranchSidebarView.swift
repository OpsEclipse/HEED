import SwiftUI

struct ProjectBranchSidebarView: View {
    let workspace: TerminalShellWorkspace
    let onTasks: () -> Void
    let onNewSession: () -> Void
    let onSelectBranch: (TerminalShellProject, TerminalShellBranch) -> Void
    let onSelectTab: (TerminalShellProject, TerminalShellBranch, TerminalShellBranchTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarAction("tasks", identifier: "sidebar-tasks", action: onTasks)
            sidebarAction("new session", identifier: "sidebar-new-session", action: onNewSession)

            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(height: HeedTheme.Stroke.brutalist)
                .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workspace.projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .heedHiddenScrollBars()
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderStrong)
                .frame(width: HeedTheme.Stroke.brutalist)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-branch-sidebar")
    }

    private func sidebarAction(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private func projectSection(_ project: TerminalShellProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .accessibilityLabel(project.name)
                .accessibilityIdentifier("project-row-\(project.id)")

            ForEach(project.branches) { branch in
                branchSection(branch, in: project)
            }
        }
    }

    private func branchSection(_ branch: TerminalShellBranch, in project: TerminalShellProject) -> some View {
        let isSelected = branch.id == workspace.selectedBranchID

        return VStack(alignment: .leading, spacing: 2) {
            Button {
                onSelectBranch(project, branch)
            } label: {
                Text(branch.name)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    .overlay(alignment: .leading) {
                        if isSelected {
                            Rectangle()
                                .fill(HeedTheme.ColorToken.textPrimary)
                                .frame(width: 3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(branch.name)
            .accessibilityIdentifier("branch-row-\(branch.id)")

            ForEach(branch.tabs) { tab in
                Button {
                    onSelectTab(project, branch, tab)
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: tab.id == workspace.selectedBranchTabID ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(tab.id == workspace.selectedBranchTabID ? HeedTheme.ColorToken.textPrimary : HeedTheme.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 30)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("branch-tab-\(tab.id)")
            }
        }
    }
}
