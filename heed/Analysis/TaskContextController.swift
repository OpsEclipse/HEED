import Combine
import Foundation

@MainActor
final class TaskContextController: ObservableObject {
    @Published private(set) var panelState: TaskContextPanelState = .idle
    @Published private(set) var selectedTaskID: String?

    private let compiler: any TaskContextCompiling
    private var activeRequestID = UUID()

    init(compiler: any TaskContextCompiling) {
        self.compiler = compiler
    }

    var selectedTask: CompiledTask? {
        switch panelState {
        case .idle:
            return nil
        case .loading(let task):
            return task
        case .loaded(let content):
            return content.task
        case .failed(let task, _):
            return task
        }
    }

    func prepareTaskContext(for task: CompiledTask, in session: TranscriptSession) {
        let requestID = UUID()
        activeRequestID = requestID
        selectedTaskID = task.id
        panelState = .loading(task: task)

        let compiler = compiler
        Task { [weak self] in
            do {
                let content = try await compiler.prepareTaskContext(session: session, task: task)
                try Task.checkCancellation()

                await MainActor.run {
                    guard let self, self.activeRequestID == requestID else {
                        return
                    }

                    self.panelState = .loaded(content)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard let self, self.activeRequestID == requestID else {
                        return
                    }

                    self.panelState = .failed(task: task, message: error.localizedDescription)
                }
            }
        }
    }

    func reset() {
        activeRequestID = UUID()
        selectedTaskID = nil
        panelState = .idle
    }
}
