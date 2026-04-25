import SwiftUI

struct TaskPrepTerminalView: View {
    @ObservedObject var controller: TaskPrepController
    @State private var draftInput = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(HeedTheme.ColorToken.borderSubtle)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(terminalText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .id("terminal-output")
                }
                .heedHiddenScrollBars()
                .scrollIndicators(.hidden)
                .background(Color.black.opacity(0.24))
                .onChange(of: controller.viewState.terminalOutput) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo("terminal-output", anchor: .bottom)
                    }
                }
            }

            Divider()
                .overlay(HeedTheme.ColorToken.borderSubtle)

            inputRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .accessibilityIdentifier("task-prep-terminal")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent terminal")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            if let taskTitle = controller.activeTaskTitle {
                Text(taskTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task-prep-terminal-status")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Type into Codex", text: $draftInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(HeedTheme.ColorToken.panel)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
                }
                .disabled(!canSendInput)
                .accessibilityIdentifier("task-prep-terminal-input")
                .onSubmit(sendInput)

            Button("Send", action: sendInput)
                .buttonStyle(
                    HeedTransportButtonStyle(
                        fillColor: HeedTheme.ColorToken.actionYellow,
                        textColor: Color.black.opacity(0.82),
                        size: .compact
                    )
                )
                .disabled(!canSendInput || draftInput.isEmpty)
                .accessibilityIdentifier("task-prep-terminal-send")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var terminalText: String {
        let output = controller.viewState.terminalOutput
        return output.isEmpty ? statusText : output
    }

    private var canSendInput: Bool {
        if case .running = controller.viewState.terminalStatus {
            return true
        }

        return false
    }

    var statusText: String {
        switch controller.viewState.terminalStatus {
        case .idle:
            return "Waiting for spawn approval."
        case .launching:
            return "Starting Codex."
        case .running:
            return "Codex is running."
        case let .failed(message):
            return message
        case let .ended(exitCode):
            if let exitCode {
                return "Codex exited with code \(exitCode)."
            }

            return "Codex exited."
        }
    }

    private var statusColor: Color {
        switch controller.viewState.terminalStatus {
        case .failed:
            return HeedTheme.ColorToken.warning
        case .launching, .running:
            return HeedTheme.ColorToken.actionYellow
        case .idle, .ended:
            return HeedTheme.ColorToken.textSecondary
        }
    }

    private func sendInput() {
        guard canSendInput else {
            return
        }

        let input = draftInput
        draftInput = ""
        controller.sendTerminalInput(input + "\n")
    }
}
