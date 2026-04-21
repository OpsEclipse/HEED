import SwiftUI

struct TaskPrepContextPanelView: View {
    @ObservedObject var controller: TaskPrepController
    let onClose: () -> Void

    private var displayedDraft: TaskPrepContextDraft? {
        controller.viewState.stableContextDraft ?? controller.viewState.pendingContextDraft
    }

    private var isUpdatingDraft: Bool {
        controller.viewState.pendingContextDraft != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let displayedDraft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if isUpdatingDraft, controller.viewState.stableContextDraft != nil {
                            statusBadge("Updating brief...")
                        }

                        draftSection("Summary", lines: [displayedDraft.summary])
                        draftSection("Goal", lines: [displayedDraft.goal])
                        draftSection("Constraints", lines: displayedDraft.constraints)
                        draftSection("Acceptance", lines: displayedDraft.acceptanceCriteria)
                        draftSection("Risks", lines: displayedDraft.risks)
                        draftSection("Open questions", lines: displayedDraft.openQuestions)
                        evidenceSection(displayedDraft.evidence)
                        spawnSection(for: displayedDraft)
                    }
                    .padding(.bottom, 20)
                }
                .heedHiddenScrollBars()
                .scrollIndicators(.hidden)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(width: 344)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.panel)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(HeedTheme.ColorToken.borderSubtle)
                .frame(width: 1)
        }
        .accessibilityIdentifier("task-prep-context-panel")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context brief")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)

                    if let taskTitle = controller.activeTaskTitle {
                        Text(taskTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .accessibilityIdentifier("task-prep-close")
            }

            Text(turnStatusText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(turnStatusColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBadge("Waiting for the first draft...")

            Text("Heed will pin a stable brief here as the assistant finishes each turn.")
                .font(.system(size: 14))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func draftSection(_ title: String, lines: [String]) -> some View {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            if cleanedLines.isEmpty {
                Text("No details yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(cleanedLines.enumerated()), id: \.offset) { index, line in
                        if cleanedLines.count == 1 {
                            Text(line)
                                .font(.system(size: 14))
                                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)

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
    }

    private func evidenceSection(_ evidence: [TaskPrepEvidence]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Evidence")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            if evidence.isEmpty {
                Text("No transcript evidence attached yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.label)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

                            Text(item.excerpt)
                                .font(.system(size: 13))
                                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(HeedTheme.ColorToken.canvas)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
                        }
                    }
                }
            }
        }
    }

    private func spawnSection(for draft: TaskPrepContextDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spawn approval")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            Text(spawnStatusText(readyToSpawn: draft.readyToSpawn))
                .font(.system(size: 14))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let request = controller.viewState.pendingSpawnRequest {
                Text(request.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.viewState.spawnStatus == .blockedWaitingForApproval {
                Button("Approve spawn") {
                    controller.approveSpawn()
                }
                .buttonStyle(
                    HeedTransportButtonStyle(
                        fillColor: HeedTheme.ColorToken.actionYellow,
                        textColor: Color.black.opacity(0.82),
                        size: .compact
                    )
                )
                .accessibilityIdentifier("task-prep-approve-spawn")
            }
        }
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(HeedTheme.ColorToken.actionYellow)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(HeedTheme.ColorToken.canvas)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
            }
    }

    private var turnStatusText: String {
        switch controller.viewState.turnState {
        case .idle:
            return "Waiting for prep."
        case .streaming:
            return "Streaming the latest turn."
        case let .failed(message):
            return message
        case .completed:
            return "Stable brief pinned."
        }
    }

    private var turnStatusColor: Color {
        switch controller.viewState.turnState {
        case .failed:
            return HeedTheme.ColorToken.warning
        case .streaming:
            return HeedTheme.ColorToken.actionYellow
        case .idle, .completed:
            return HeedTheme.ColorToken.textSecondary
        }
    }

    private func spawnStatusText(readyToSpawn: Bool) -> String {
        switch controller.viewState.spawnStatus {
        case .idle:
            return readyToSpawn ? "The draft says this task is ready, but no spawn request has arrived yet." : "The assistant has not asked to spawn an agent yet."
        case .approvalGranted:
            return "Approval is saved. Heed will unblock the next matching spawn request."
        case .blockedWaitingForApproval:
            return "The assistant asked to spawn an agent. Review the brief, then approve when it looks right."
        case .readyToSpawn:
            return "Spawn is approved for this task."
        }
    }
}
