import SwiftUI

struct TaskAnalysisSectionView: View {
    @ObservedObject var controller: TaskAnalysisController

    var body: some View {
        if let section = controller.sectionModel {
            VStack(alignment: .leading, spacing: 16) {
                header(for: section)

                if section.isExpanded {
                    expandedContent(for: section)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HeedTheme.ColorToken.panel.opacity(0.9))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-analysis-section")
        }
    }

    private func header(for section: TaskAnalysisController.SectionModel) -> some View {
        Button {
            controller.toggleSectionExpansion()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)

                    if let helperText = section.helperText {
                        Text(helperText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Text(section.isExpanded ? "Hide" : "Show")
                    Image(systemName: section.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-analysis-header")
    }

    @ViewBuilder
    private func expandedContent(for section: TaskAnalysisController.SectionModel) -> some View {
        if let statusText = section.statusText {
            HStack(spacing: 10) {
                if section.isCompiling {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HeedTheme.ColorToken.actionYellow)
                }

                Text(statusText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            }
        }

        if let errorText = section.errorText {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.warning)

                if let retryTitle = section.retryTitle {
                    quietAction(title: retryTitle, accessibilityIdentifier: "task-analysis-inline-retry") {
                        controller.handleCompileAction()
                    }
                }
            }
        }

        if let result = section.result {
            if !result.warnings.isEmpty {
                warningStack(result.warnings)
            }

            taskGroup(
                tasks: result.tasks,
                selectedTaskIDs: section.selectedTaskIDs,
                noTasksReason: result.noTasksReason
            )

            if !result.decisions.isEmpty {
                noteGroup(
                    title: "Decisions",
                    notes: result.decisions,
                    isExpanded: section.isDecisionsExpanded,
                    accessibilityIdentifier: "task-analysis-decisions-toggle",
                    toggle: controller.toggleDecisionsExpansion
                )
            }

            if !result.followUps.isEmpty {
                noteGroup(
                    title: "Follow-ups",
                    notes: result.followUps,
                    isExpanded: section.isFollowUpsExpanded,
                    accessibilityIdentifier: "task-analysis-follow-ups-toggle",
                    toggle: controller.toggleFollowUpsExpansion
                )
            }
        }
    }

    private func warningStack(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func taskGroup(
        tasks: [CompiledTask],
        selectedTaskIDs: Set<String>,
        noTasksReason: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            groupTitle("Tasks", count: tasks.count, isExpanded: true, toggle: nil)

            if tasks.isEmpty {
                Text(noTasksReason ?? "No clear tasks found")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .accessibilityIdentifier("task-analysis-no-tasks")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRowView(
                            task: task,
                            isSelected: selectedTaskIDs.contains(task.id),
                            spawnedTaskID: controller.lastSpawnedTaskID,
                            onToggleSelection: {
                                controller.toggleTaskSelection(task.id)
                            },
                            onSpawnAgent: {
                                controller.requestSpawnAgent(for: task.id)
                            },
                            onShowSource: {
                                controller.showSource(for: task.evidenceSegmentIDs)
                            }
                        )

                        if index < tasks.count - 1 {
                            Divider()
                                .overlay(HeedTheme.ColorToken.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private func noteGroup(
        title: String,
        notes: [CompiledNote],
        isExpanded: Bool,
        accessibilityIdentifier: String,
        toggle: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            groupTitle(
                title,
                count: notes.count,
                isExpanded: isExpanded,
                accessibilityIdentifier: accessibilityIdentifier,
                toggle: toggle
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        NoteRowView(
                            note: note,
                            onShowSource: {
                                controller.showSource(for: note.evidenceSegmentIDs)
                            }
                        )

                        if index < notes.count - 1 {
                            Divider()
                                .overlay(HeedTheme.ColorToken.borderSubtle)
                        }
                    }
                }
            }
        }
    }

    private func groupTitle(
        _ title: String,
        count: Int,
        isExpanded: Bool,
        accessibilityIdentifier: String? = nil,
        toggle: (() -> Void)?
    ) -> some View {
        Group {
            if let toggle {
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Text(title)
                        Text("\(count)")
                            .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                        Spacer(minLength: 12)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
            } else {
                HStack(spacing: 8) {
                    Text(title)
                    Text("\(count)")
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
            }
        }
    }

    private func quietAction(
        title: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TaskRowView: View {
    let task: CompiledTask
    let isSelected: Bool
    let spawnedTaskID: String?
    let onToggleSelection: () -> Void
    let onSpawnAgent: () -> Void
    let onShowSource: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? HeedTheme.ColorToken.actionYellow : HeedTheme.ColorToken.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-row-toggle-\(task.id)")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(task.type.rawValue)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HeedTheme.ColorToken.panelRaised.opacity(0.75))

                    Spacer(minLength: 12)

                    spawnAgentButton
                }

                Text(task.details)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)

                if let assigneeHint = task.assigneeHint {
                    Text("Assignee hint: \(assigneeHint)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                }

                evidenceLine(text: task.evidenceExcerpt)

                Button(action: onShowSource) {
                    Text("Show source")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("task-row-source-\(task.id)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    private var spawnAgentButton: some View {
        Button(action: onSpawnAgent) {
            HStack(spacing: 6) {
                Text(spawnButtonTitle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .semibold, design: .default))
        }
        .buttonStyle(
            HeedTransportButtonStyle(
                fillColor: HeedTheme.ColorToken.actionYellow,
                textColor: Color.black.opacity(0.8),
                size: .compact
            )
        )
        .accessibilityLabel(spawnButtonTitle)
        .accessibilityIdentifier("task-row-spawn-agent-\(task.id)")
    }

    private var spawnButtonTitle: String {
        spawnedTaskID == task.id ? "Spawning..." : "Spawn agent"
    }

    private func evidenceLine(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Evidence")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            Text("\"\(text)\"")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NoteRowView: View {
    let note: CompiledNote
    let onShowSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.title)
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)

            Text(note.details)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Evidence")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)

                Text("\"\(note.evidenceExcerpt)\"")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onShowSource) {
                Text("Show source")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
    }
}
