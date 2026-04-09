import Foundation
import SwiftWhisper

struct Request: Decodable {
    let chunkID: UUID
    let inputPath: String
}

struct Response: Encodable {
    struct Segment: Encodable {
        let startTimeMs: Int
        let endTimeMs: Int
        let text: String
    }

    let chunkID: UUID
    let segments: [Segment]?
    let error: String?
}

enum CLIError: LocalizedError {
    case missingModelPath
    case unreadableInput(String)

    var errorDescription: String? {
        switch self {
        case .missingModelPath:
            return "Missing --model path."
        case .unreadableInput(let path):
            return "Could not read input chunk at \(path)."
        }
    }
}

@main
struct WhisperChunkCLI {
    static func main() async {
        do {
            let modelURL = try modelURL(from: CommandLine.arguments)
            let whisper = Whisper(fromFileURL: modelURL, withParams: configuredParams())

            while let line = readLine(), !line.isEmpty {
                let response = await handle(line: line, whisper: whisper)
                write(response: response)
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func modelURL(from arguments: [String]) throws -> URL {
        guard let modelFlagIndex = arguments.firstIndex(of: "--model"),
              arguments.indices.contains(modelFlagIndex + 1) else {
            throw CLIError.missingModelPath
        }

        return URL(fileURLWithPath: arguments[modelFlagIndex + 1])
    }

    private static func configuredParams() -> WhisperParams {
        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        return params
    }

    private static func handle(line: String, whisper: Whisper) async -> Response {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            let audioFrames = try loadPCMFrames(at: request.inputPath)
            let segments = try await whisper.transcribe(audioFrames: audioFrames)
            return Response(
                chunkID: request.chunkID,
                segments: segments.map {
                    Response.Segment(
                        startTimeMs: $0.startTime,
                        endTimeMs: $0.endTime,
                        text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                },
                error: nil
            )
        } catch {
            let chunkID = (try? JSONDecoder().decode(Request.self, from: Data(line.utf8)).chunkID) ?? UUID()
            return Response(chunkID: chunkID, segments: nil, error: error.localizedDescription)
        }
    }

    private static func loadPCMFrames(at path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            throw CLIError.unreadableInput(path)
        }
        guard !data.isEmpty else {
            return []
        }

        return data.withUnsafeBytes { rawBuffer in
            let sampleCount = rawBuffer.count / MemoryLayout<Int16>.stride
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { index in
                max(-1.0, min(Float(samples[index]) / Float(Int16.max), 1.0))
            }
        }
    }

    private static func write(response: Response) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        guard let data = try? encoder.encode(response) else {
            return
        }

        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
        fflush(stdout)
    }
}
