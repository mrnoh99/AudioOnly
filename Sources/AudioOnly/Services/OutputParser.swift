import Foundation

enum ParseEvent {
    case progress(Double)
    case title(String)
    case outputFile(String)
}

/// 실행 중인 명령의 출력을 해석하고 로그/오류를 모은다. 파이프 스레드에서 호출된다.
final class OutputState: @unchecked Sendable {
    private static let maxLogLines = 500

    private let lock = NSLock()
    private var lines: [String] = []
    private var errorLine: String?
    private var file: String?
    private var duration: Double?

    var logLines: [String] { locked { lines } }
    var lastError: String? { locked { errorLine } }
    var outputFile: String? { locked { file } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func appendLog(_ line: String) {
        lines.append(line)
        if lines.count > Self.maxLogLines {
            lines.removeFirst(lines.count - Self.maxLogLines)
        }
    }

    // MARK: yt-dlp

    func handleYTDLP(_ line: String) -> ParseEvent? {
        if line.hasPrefix(YTDLPCommand.progressPrefix) {
            let value = Self.firstNumber(in: line.dropFirst(YTDLPCommand.progressPrefix.count))
            return value.map { .progress(min(max($0 / 100, 0), 1)) }
        }
        return locked {
            appendLog(line)
            if line.hasPrefix(YTDLPCommand.titlePrefix) {
                return .title(String(line.dropFirst(YTDLPCommand.titlePrefix.count)))
            }
            if line.hasPrefix(YTDLPCommand.filePrefix) {
                let path = String(line.dropFirst(YTDLPCommand.filePrefix.count))
                file = path
                return .outputFile(path)
            }
            if line.hasPrefix("ERROR:") {
                errorLine = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }

    // MARK: ffmpeg (-progress pipe:1)

    func handleFFmpeg(_ line: String, stream: ProcessOutputStream) -> ParseEvent? {
        if stream == .stdout {
            // key=value 형식의 진행률 출력
            guard line.hasPrefix("out_time=") else { return nil }
            let seconds = Self.parseTimestamp(String(line.dropFirst("out_time=".count)))
            return locked {
                guard let seconds, let total = duration, total > 0 else { return nil }
                return .progress(min(max(seconds / total, 0), 1))
            }
        }
        return locked {
            appendLog(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if duration == nil, trimmed.hasPrefix("Duration:") {
                let value = trimmed.dropFirst("Duration:".count).split(separator: ",").first.map(String.init) ?? ""
                duration = Self.parseTimestamp(value.trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty && !line.hasPrefix(" ") {
                // ffmpeg는 실패 원인을 마지막 부분에 들여쓰기 없이 출력한다.
                errorLine = trimmed
            }
            return nil
        }
    }

    // MARK: helpers

    static func firstNumber<S: StringProtocol>(in text: S) -> Double? {
        var digits = ""
        for character in text {
            if character.isNumber || (character == "." && !digits.isEmpty && !digits.contains(".")) {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return Double(digits)
    }

    /// "01:02:03.45" -> 3723.45
    static func parseTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2])
        else { return nil }
        return h * 3600 + m * 60 + s
    }
}
