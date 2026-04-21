import Foundation

protocol TaskPrepConversationServicing: Sendable {
    func beginTurn(input: TaskPrepTurnInput) -> AsyncThrowingStream<TaskPrepConversationEvent, Error>
}
