import SwiftUI

struct TaskPrepWorkspaceView: View {
    let chatWidthFraction = 0.6
    let contextWidthFraction = 0.4

    @ObservedObject var controller: TaskPrepController
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Group {
                    if shouldShowTerminal(for: controller.viewState.terminalStatus) {
                        TaskPrepTerminalView(controller: controller)
                    } else {
                        TaskPrepChatView(controller: controller)
                            .accessibilityIdentifier("task-prep-chat")
                    }
                }
                    .frame(width: geometry.size.width * chatWidthFraction)

                TaskPrepContextPanelView(
                    controller: controller,
                    onClose: onClose
                )
                .frame(width: geometry.size.width * contextWidthFraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(HeedTheme.ColorToken.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-prep-workspace")
    }

    func shouldShowTerminal(for status: TaskPrepTerminalStatus) -> Bool {
        switch status {
        case .idle:
            return false
        case .launching, .running, .failed, .ended:
            return true
        }
    }
}
