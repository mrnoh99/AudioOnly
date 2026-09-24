import Foundation

enum ProcessOutputStream {
    case stdout
    case stderr
}

/// 파이프에서 들어오는 바이트를 줄 단위(\n 또는 \r)로 잘라 전달한다.
/// yt-dlp/ffmpeg는 진행률을 \r 로 갱신하므로 둘 다 줄 끝으로 취급한다.
final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var scanOffset = 0
    private var finished = false
    private let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        var lineStart = 0
        var index = scanOffset
        let count = buffer.count
        buffer.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            while index < count {
                let byte = bytes[index]
                if byte == 0x0A || byte == 0x0D {
                    if index > lineStart {
                        lines.append(String(decoding: bytes[lineStart..<index], as: UTF8.self))
                    }
                    lineStart = index + 1
                }
                index += 1
            }
        }
        if lineStart > 0 {
            buffer.removeSubrange(0..<lineStart)
            buffer = Data(buffer) // 인덱스를 0부터 다시 시작
        }
        scanOffset = buffer.count
        lock.unlock()
        lines.forEach(handler)
    }

    /// 남은 데이터를 마지막 줄로 내보낸다. 처음 호출될 때만 true를 반환한다.
    func finish() -> Bool {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return false
        }
        finished = true
        let rest = buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        scanOffset = 0
        lock.unlock()
        if let rest { handler(rest) }
        return true
    }
}

/// 앱 종료 시 실행 중인 하위 프로세스를 정리하기 위한 레지스트리
final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func add(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    func remove(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = nil
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let all = Array(processes.values)
        lock.unlock()
        for process in all where process.isRunning {
            process.terminate()
        }
    }
}

/// 외부 명령(yt-dlp, ffmpeg)을 실행하고 출력을 줄 단위로 스트리밍한다. 한 인스턴스는 한 번만 실행한다.
final class RunningProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    /// 프로세스를 실행하고 종료 코드를 반환한다. Task가 취소되면 프로세스도 종료된다.
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        onLine: @escaping @Sendable (String, ProcessOutputStream) -> Void
    ) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await launch(executable: executable, arguments: arguments, environment: environment, onLine: onLine)
        } onCancel: {
            self.cancel()
        }
    }

    private func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        onLine: @escaping @Sendable (String, ProcessOutputStream) -> Void
    ) async throws -> Int32 {
        if wasCancelled { throw CancellationError() }

        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let group = DispatchGroup()
        let streams: [(Pipe, LineSplitter)] = [
            (outPipe, LineSplitter { onLine($0, .stdout) }),
            (errPipe, LineSplitter { onLine($0, .stderr) }),
        ]
        for (pipe, splitter) in streams {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if splitter.finish() { group.leave() }
                } else {
                    splitter.append(data)
                }
            }
        }

        let process = self.process
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                ProcessRegistry.shared.remove(finished)
                DispatchQueue.global().async {
                    // 손자 프로세스가 파이프를 붙잡고 있을 수 있으므로 무한 대기하지 않는다.
                    _ = group.wait(timeout: .now() + 3)
                    continuation.resume(returning: finished.terminationStatus)
                }
            }
            do {
                try process.run()
                ProcessRegistry.shared.add(process)
                try? outPipe.fileHandleForWriting.close()
                try? errPipe.fileHandleForWriting.close()
                if wasCancelled { process.terminate() }
            } catch {
                for (pipe, _) in streams {
                    pipe.fileHandleForReading.readabilityHandler = nil
                }
                continuation.resume(throwing: error)
            }
        }
    }
}

/// 여러 스레드에서 줄을 모으는 단순한 수집기
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutLines: [String] = []
    private var stderrLines: [String] = []

    func append(_ line: String, _ stream: ProcessOutputStream) {
        lock.lock()
        switch stream {
        case .stdout: stdoutLines.append(line)
        case .stderr: stderrLines.append(line)
        }
        lock.unlock()
    }

    var stdout: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stdoutLines
    }

    var stderr: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stderrLines
    }
}
