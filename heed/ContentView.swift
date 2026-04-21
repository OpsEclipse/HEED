import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var controller: RecordingController
    @State private var taskAnalysisController: TaskAnalysisController
    @State private var taskPrepController: TaskPrepController
    @State private var apiKeySettingsViewModel: APIKeySettingsViewModel
    private let isUITestMode: Bool

    @MainActor
    init(
        controller: RecordingController,
        taskAnalysisController: TaskAnalysisController? = nil,
        taskPrepController: TaskPrepController? = nil,
        apiKeySettingsViewModel: APIKeySettingsViewModel? = nil,
        processInfo: ProcessInfo = .processInfo
    ) {
        isUITestMode = processInfo.arguments.contains("--heed-ui-test")
        _controller = StateObject(wrappedValue: controller)
        _taskAnalysisController = State(
            initialValue: taskAnalysisController ?? makeTaskAnalysisController(processInfo: processInfo)
        )
        _taskPrepController = State(
            initialValue: taskPrepController ?? makeTaskPrepController(processInfo: processInfo)
        )
        _apiKeySettingsViewModel = State(
            initialValue: apiKeySettingsViewModel ?? APIKeySettingsViewModel()
        )
    }

    var body: some View {
        WorkspaceShell(
            controller: controller,
            taskAnalysisController: taskAnalysisController,
            taskPrepController: taskPrepController,
            apiKeySettingsViewModel: apiKeySettingsViewModel
        )
        .background(HeedTheme.ColorToken.canvas)
        .task {
            guard isUITestMode else {
                return
            }

            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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

func makeTaskPrepController(processInfo: ProcessInfo = .processInfo) -> TaskPrepController {
    let service: any TaskPrepConversationServicing

    if processInfo.arguments.contains("--heed-ui-test") {
        service = TaskPrepFixtureConversationService(processInfo: processInfo)
    } else {
        service = OpenAITaskPrepConversationService()
    }

    return TaskPrepController(service: service)
}

#Preview {
    ContentView(controller: RecordingController(demoMode: true))
}
