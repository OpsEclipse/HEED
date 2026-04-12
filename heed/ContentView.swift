import SwiftUI

struct ContentView: View {
    @StateObject private var controller: RecordingController
    @State private var taskAnalysisController: TaskAnalysisController
    @State private var taskContextController: TaskContextController
    @State private var apiKeySettingsViewModel: APIKeySettingsViewModel

    @MainActor
    init(
        controller: RecordingController,
        taskAnalysisController: TaskAnalysisController? = nil,
        taskContextController: TaskContextController? = nil,
        apiKeySettingsViewModel: APIKeySettingsViewModel? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        _controller = StateObject(wrappedValue: controller)
        _taskAnalysisController = State(
            initialValue: taskAnalysisController ?? makeTaskAnalysisController(processInfo: processInfo)
        )
        _taskContextController = State(
            initialValue: taskContextController ?? makeTaskContextController(processInfo: processInfo)
        )
        _apiKeySettingsViewModel = State(
            initialValue: apiKeySettingsViewModel ?? APIKeySettingsViewModel()
        )
    }

    var body: some View {
        WorkspaceShell(
            controller: controller,
            taskAnalysisController: taskAnalysisController,
            taskContextController: taskContextController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )
        .background(HeedTheme.ColorToken.canvas)
    }
}

func makeTaskAnalysisController(processInfo: ProcessInfo = .processInfo) -> TaskAnalysisController {
    let compiler: any TaskAnalysisCompiling

    if processInfo.arguments.contains("--heed-ui-test") {
        compiler = TaskAnalysisFixtureCompiler(processInfo: processInfo)
    } else {
        compiler = OpenAITaskAnalysisCompiler()
    }

    return TaskAnalysisController(compiler: compiler)
}

func makeTaskContextController(processInfo: ProcessInfo = .processInfo) -> TaskContextController {
    let compiler: any TaskContextCompiling

    if processInfo.arguments.contains("--heed-ui-test") {
        compiler = TaskContextFixtureCompiler()
    } else {
        compiler = OpenAITaskContextCompiler()
    }

    return TaskContextController(compiler: compiler)
}

#Preview {
    ContentView(controller: RecordingController(demoMode: true))
}
