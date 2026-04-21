import SwiftUI

struct TaskPrepWorkspaceView: View {
    @ObservedObject var controller: TaskPrepController
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TaskPrepChatView(controller: controller)

            TaskPrepContextPanelView(
                controller: controller,
                onClose: onClose
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HeedTheme.ColorToken.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-prep-workspace")
    }
}
