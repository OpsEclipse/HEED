import Combine
import Foundation

@MainActor
final class TaskPrepController: ObservableObject {
    @Published private(set) var viewState = TaskPrepViewState()

    private let service: any TaskPrepConversationServicing
    private var activeTurnStream: AsyncThrowingStream<TaskPrepConversationEvent, Error>?

    init(service: any TaskPrepConversationServicing) {
        self.service = service
    }

    func start(task: CompiledTask, in session: TranscriptSession) {
        viewState = TaskPrepViewState(
            messages: [TaskPrepMessage(role: .assistant, text: "")],
            turnState: .streaming
        )

        activeTurnStream = service.beginTurn(input: TaskPrepTurnInput(task: task, session: session))
    }
}
