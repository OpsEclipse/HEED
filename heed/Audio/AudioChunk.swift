import Foundation

struct AudioChunk: Sendable {
    let source: AudioSource
    let startedFrame: Int
    let startedAt: TimeInterval
    let frames: [Float]
}
