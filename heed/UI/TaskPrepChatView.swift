import SwiftUI

struct TaskPrepChatView: View {
    @ObservedObject var controller: TaskPrepController
    @State private var draftMessage = ""

    private var statusText: String {
        switch controller.viewState.turnState {
        case .idle:
            return "Start task prep to open the workspace."
        case .streaming:
            return "Heed is preparing context."
        case let .failed(message):
            return message
        case .completed:
            return "Ask a follow-up to refine the brief."
        }
    }

    private var canSendMessage: Bool {
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        controller.viewState.turnState != .streaming
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(HeedTheme.ColorToken.borderSubtle)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(controller.viewState.messages) { message in
                            TaskPrepMessageBubble(
                                message: message,
                                isLatestStreamingAssistant: isLatestStreamingAssistant(message)
                            )
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
                .heedHiddenScrollBars()
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("task-prep-chat-thread")
                .onAppear {
                    scrollToLatestMessage(with: proxy)
                }
                .onChange(of: controller.viewState.messages.count) {
                    scrollToLatestMessage(with: proxy)
                }
                .onChange(of: controller.viewState.messages.last?.text) {
                    scrollToLatestMessage(with: proxy)
                }
            }

            Divider()
                .overlay(HeedTheme.ColorToken.borderSubtle)

            inputRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prep workspace")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask a follow-up about the task", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HeedTheme.ColorToken.panel)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HeedTheme.ColorToken.borderSubtle, lineWidth: 1)
                }
                .accessibilityIdentifier("task-prep-chat-input")
                .onSubmit(sendMessage)

            Button("Send", action: sendMessage)
                .buttonStyle(
                    HeedTransportButtonStyle(
                        fillColor: HeedTheme.ColorToken.actionYellow,
                        textColor: Color.black.opacity(0.82),
                        size: .compact
                    )
                )
                .disabled(!canSendMessage)
                .accessibilityIdentifier("task-prep-chat-send")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var statusColor: Color {
        switch controller.viewState.turnState {
        case .failed:
            return HeedTheme.ColorToken.warning
        case .streaming:
            return HeedTheme.ColorToken.actionYellow
        case .idle, .completed:
            return HeedTheme.ColorToken.textSecondary
        }
    }

    private func sendMessage() {
        let message = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }

        draftMessage = ""
        controller.sendUserMessage(message)
    }

    private func scrollToLatestMessage(with proxy: ScrollViewProxy) {
        guard let latestMessageID = controller.viewState.messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(latestMessageID, anchor: .bottom)
        }
    }

    private func isLatestStreamingAssistant(_ message: TaskPrepMessage) -> Bool {
        guard controller.viewState.turnState == .streaming,
              message.role == .assistant else {
            return false
        }

        return controller.viewState.messages.last(where: { $0.role == .assistant })?.id == message.id
    }
}

struct TaskPrepMessageBubble: View {
    let message: TaskPrepMessage
    let isLatestStreamingAssistant: Bool

    init(
        message: TaskPrepMessage,
        isLatestStreamingAssistant: Bool = false
    ) {
        self.message = message
        self.isLatestStreamingAssistant = isLatestStreamingAssistant
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            Text(roleLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                if shouldShowMessageText {
                    Text(displayedText)
                        .font(.system(size: 14))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsLoadingIndicator {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HeedTheme.ColorToken.actionYellow)
                        .accessibilityLabel("Assistant response is loading")
                        .accessibilityIdentifier("task-prep-assistant-loading")
                }
            }
                .frame(maxWidth: usesContentWidth ? 560 : .infinity, alignment: .leading)
                .padding(.horizontal, usesFlatChrome ? 0 : 14)
                .padding(.vertical, usesFlatChrome ? 0 : 12)
                .background {
                    if !usesFlatChrome {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(bubbleFill)
                    }
                }
                .overlay {
                    if !usesFlatChrome {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(bubbleBorder, lineWidth: 1)
                    }
                }
        }
        .frame(maxWidth: 560, alignment: bubbleAlignment)
        .frame(maxWidth: .infinity, alignment: bubbleAlignment)
    }

    var usesFlatChrome: Bool {
        message.role == .assistant
    }

    var usesContentWidth: Bool {
        message.role == .user
    }

    var showsLoadingIndicator: Bool {
        message.role == .assistant && isLatestStreamingAssistant && !message.isInterrupted
    }

    private var shouldShowMessageText: Bool {
        !message.text.isEmpty || !showsLoadingIndicator
    }

    private var displayedText: String {
        message.text.isEmpty ? " " : message.text
    }

    private var roleLabel: String {
        switch message.role {
        case .assistant:
            return message.isInterrupted ? "ASSISTANT • INTERRUPTED" : "ASSISTANT"
        case .user:
            return "YOU"
        case .system:
            return "SYSTEM"
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleAlignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleFill: some ShapeStyle {
        switch message.role {
        case .assistant:
            return HeedTheme.ColorToken.panel
        case .user:
            return HeedTheme.ColorToken.panelRaised
        case .system:
            return HeedTheme.ColorToken.panel
        }
    }

    private var bubbleBorder: Color {
        if message.isInterrupted {
            return HeedTheme.ColorToken.warning
        }

        switch message.role {
        case .assistant, .system:
            return HeedTheme.ColorToken.borderSubtle
        case .user:
            return HeedTheme.ColorToken.borderStrong
        }
    }
}
