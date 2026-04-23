import Foundation

protocol MicCaptureManaging {
    func start(onFrames: @escaping @Sendable ([Float]) -> Void) throws
    func stop()
}

protocol SystemAudioCaptureManaging {
    func start(
        onFrames: @escaping @Sendable ([Float]) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) async throws

    func stop() async
}
