import Foundation

struct AudioChunk: Sendable {
    let source: AudioSource
    let startedAt: TimeInterval
    let frames: [Float]
}
