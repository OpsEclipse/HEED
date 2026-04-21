import Combine
import Foundation

@MainActor
final class TaskPrepController: ObservableObject {
    @Published private(set) var viewState = TaskPrepViewState()

    private let service: any TaskPrepConversationServicing

    init(service: any TaskPrepConversationServicing) {
        self.service = service
    }

    func start(task: CompiledTask, in session: TranscriptSession) {
        viewState = TaskPrepViewState(
            messages: [TaskPrepMessage(role: .assistant, text: "")],
            turnState: .streaming
        )

        _ = service.beginTurn(input: TaskPrepTurnInput(task: task, session: session))
    }
}
