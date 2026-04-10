import SwiftUI

struct ContentView: View {
    @StateObject private var controller: RecordingController
    @State private var taskAnalysisController: TaskAnalysisController

    @MainActor
    init(
        controller: RecordingController,
        taskAnalysisController: TaskAnalysisController? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        _controller = StateObject(wrappedValue: controller)
        _taskAnalysisController = State(
            initialValue: taskAnalysisController ?? makeTaskAnalysisController(processInfo: processInfo)
        )
    }

    var body: some View {
        WorkspaceShell(
            controller: controller,
            taskAnalysisController: taskAnalysisController
        )
        .background(HeedTheme.ColorToken.canvas)
    }
}

func makeTaskAnalysisController(processInfo: ProcessInfo = .processInfo) -> TaskAnalysisController {
    TaskAnalysisController(compiler: TaskAnalysisFixtureCompiler(processInfo: processInfo))
}

#Preview {
    ContentView(controller: RecordingController(demoMode: true))
}
