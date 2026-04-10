import Foundation
import whisper_cpp

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
    case modelLoadFailed(String)
    case unreadableInput(String)
    case transcriptionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingModelPath:
            return "Missing --model path."
        case .modelLoadFailed(let path):
            return "Could not load Whisper model at \(path)."
        case .unreadableInput(let path):
            return "Could not read input chunk at \(path)."
        case .transcriptionFailed(let code):
            return "Whisper transcription failed with code \(code)."
        }
    }
}

private struct WhisperSegment {
    let startTimeMs: Int
    let endTimeMs: Int
    let text: String
    let averageLogProbability: Float
}

private final class WhisperEngine {
    private let context: OpaquePointer
    private let languagePointer: UnsafeMutablePointer<CChar>

    init(modelURL: URL) throws {
        guard let context = modelURL.path.withCString({ whisper_init_from_file($0) }) else {
            throw CLIError.modelLoadFailed(modelURL.path)
        }

        guard let languagePointer = strdup("en") else {
            whisper_free(context)
            throw CLIError.modelLoadFailed(modelURL.path)
        }

        self.context = context
        self.languagePointer = languagePointer
    }

    deinit {
        free(languagePointer)
        whisper_free(context)
    }

    func transcribe(audioFrames: [Float]) throws -> [WhisperSegment] {
        guard !audioFrames.isEmpty else {
            return []
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.language = UnsafePointer(languagePointer)
        params.translate = false
        params.no_context = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true

        let status = audioFrames.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }

        guard status == 0 else {
            throw CLIError.transcriptionFailed(status)
        }

        let segmentCount = whisper_full_n_segments(context)
        var segments: [WhisperSegment] = []
        segments.reserveCapacity(Int(segmentCount))

        for index in 0..<segmentCount {
            guard let textPointer = whisper_full_get_segment_text(context, index) else {
                continue
            }

            let text = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            segments.append(
                WhisperSegment(
                    startTimeMs: Int(whisper_full_get_segment_t0(context, index) * 10),
                    endTimeMs: Int(whisper_full_get_segment_t1(context, index) * 10),
                    text: text,
                    averageLogProbability: averageLogProbability(forSegmentAt: index)
                )
            )
        }

        return segments
    }

    private func averageLogProbability(forSegmentAt index: Int32) -> Float {
        let tokenCount = whisper_full_n_tokens(context, index)
        guard tokenCount > 0 else {
            return 0
        }

        var sum: Float = 0
        var countedTokens: Int32 = 0

        for tokenIndex in 0..<tokenCount {
            guard let tokenPointer = whisper_full_get_token_text(context, index, tokenIndex) else {
                continue
            }

            let tokenText = String(cString: tokenPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tokenText.isEmpty else {
                continue
            }

            let tokenData = whisper_full_get_token_data(context, index, tokenIndex)
            sum += tokenData.plog
            countedTokens += 1
        }

        guard countedTokens > 0 else {
            return 0
        }

        return sum / Float(countedTokens)
    }
}

@main
struct WhisperChunkCLI {
    private static let minimumAverageLogProbability: Float = -1.0

    static func main() async {
        do {
            let modelURL = try modelURL(from: CommandLine.arguments)
            let whisper = try WhisperEngine(modelURL: modelURL)

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

    private static func handle(line: String, whisper: WhisperEngine) async -> Response {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            let audioFrames = try loadPCMFrames(at: request.inputPath)
            let segments = try whisper.transcribe(audioFrames: audioFrames)
                .filter(shouldKeep(_:))

            return Response(
                chunkID: request.chunkID,
                segments: segments.map {
                    Response.Segment(
                        startTimeMs: $0.startTimeMs,
                        endTimeMs: $0.endTimeMs,
                        text: $0.text
                    )
                },
                error: nil
            )
        } catch {
            let chunkID = (try? JSONDecoder().decode(Request.self, from: Data(line.utf8)).chunkID) ?? UUID()
            return Response(chunkID: chunkID, segments: nil, error: error.localizedDescription)
        }
    }

    private static func shouldKeep(_ segment: WhisperSegment) -> Bool {
        guard !looksLikeSoundCaption(segment.text) else {
            return false
        }

        return segment.averageLogProbability >= minimumAverageLogProbability
    }

    private static func looksLikeSoundCaption(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last else {
            return false
        }

        return (first == "[" && last == "]") || (first == "(" && last == ")")
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
