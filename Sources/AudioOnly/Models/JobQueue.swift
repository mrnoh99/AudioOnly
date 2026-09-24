import Foundation

enum JobSource {
    /// YouTube 영상 1개 (재생목록 항목도 1개씩 작업이 된다)
    case youtube(url: String, outputTemplate: String, outputDirectory: URL)
    /// 이미 내려받은 로컬 파일에서 오디오 추출
    case localFile(input: URL, output: URL)
}

@MainActor
final class Job: ObservableObject, Identifiable {
    enum Status: Equatable {
        case pending
        case running
        case converting
        case done
        case failed(String)
        case cancelled

        var isActive: Bool { self == .running || self == .converting }

        var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            case .pending, .running, .converting: return false
            }
        }
    }

    let id = UUID()
    let source: JobSource
    let options: ExtractOptions
    /// 재생목록에서 온 경우 재생목록 제목
    let group: String?

    @Published var title: String
    @Published var status: Status = .pending
    @Published var progress: Double?
    @Published var outputURL: URL?
    @Published var log: [String] = []

    var process: RunningProcess?
    var task: Task<Void, Never>?

    init(source: JobSource, options: ExtractOptions, title: String, group: String? = nil) {
        self.source = source
        self.options = options
        self.title = title
        self.group = group
    }

    var sourceDescription: String {
        switch source {
        case .youtube(let url, _, _):
            return group.map { "재생목록: \($0)" } ?? url
        case .localFile(let input, _):
            return input.path
        }
    }

    var statusText: String {
        switch status {
        case .pending: return "대기 중"
        case .running:
            if let progress { return String(format: "%.0f%%", progress * 100) }
            return "진행 중"
        case .converting: return "변환 중"
        case .done: return "완료"
        case .failed: return "실패"
        case .cancelled: return "취소됨"
        }
    }
}

@MainActor
final class JobQueue: ObservableObject {
    @Published private(set) var jobs: [Job] = []

    var maxConcurrent = 2 {
        didSet { pump() }
    }

    func enqueue(_ newJobs: [Job]) {
        guard !newJobs.isEmpty else { return }
        jobs.append(contentsOf: newJobs)
        pump()
    }

    func cancel(_ job: Job) {
        switch job.status {
        case .pending:
            job.status = .cancelled
        case .running, .converting:
            job.process?.cancel()
            job.task?.cancel()
        case .done, .failed, .cancelled:
            break
        }
    }

    func cancelAll() {
        for job in jobs { cancel(job) }
    }

    func retry(_ job: Job) {
        guard job.status.isFinished, job.status != .done else { return }
        job.status = .pending
        job.progress = nil
        job.log = []
        pump()
    }

    func remove(_ job: Job) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.status.isFinished }
    }

    private func pump() {
        var running = jobs.filter { $0.status.isActive }.count
        for job in jobs where job.status == .pending {
            guard running < maxConcurrent else { break }
            running += 1
            start(job)
        }
    }

    private func start(_ job: Job) {
        job.status = .running
        job.progress = nil
        job.task = Task { [weak self] in
            await JobRunner.run(job)
            job.task = nil
            self?.pump()
        }
    }
}

@MainActor
enum JobRunner {
    static func run(_ job: Job) async {
        let process = RunningProcess()
        job.process = process
        defer { job.process = nil }

        let state = OutputState()
        let executable: URL
        let arguments: [String]
        let isYouTube: Bool
        let fm = FileManager.default

        switch job.source {
        case .youtube(let url, let template, let directory):
            guard let ytDlp = job.options.ytDlpURL else {
                job.status = .failed("yt-dlp를 찾을 수 없습니다.")
                return
            }
            if job.options.ffmpegURL == nil {
                job.status = .failed("ffmpeg를 찾을 수 없습니다. (brew install ffmpeg)")
                return
            }
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            executable = ytDlp
            arguments = YTDLPCommand.downloadArguments(url: url, outputTemplate: template, options: job.options)
            isYouTube = true

        case .localFile(let input, let output):
            guard let ffmpeg = job.options.ffmpegURL else {
                job.status = .failed("ffmpeg를 찾을 수 없습니다. (brew install ffmpeg)")
                return
            }
            try? fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            executable = ffmpeg
            arguments = FFmpegCommand.extractArguments(input: input, output: output, options: job.options)
            isYouTube = false
        }

        do {
            let exitCode = try await process.run(
                executable: executable,
                arguments: arguments,
                environment: ToolLocator.processEnvironment
            ) { line, stream in
                let event = isYouTube ? state.handleYTDLP(line) : state.handleFFmpeg(line, stream: stream)
                guard let event else { return }
                Task { @MainActor in JobRunner.apply(event, to: job) }
            }

            job.log = state.logLines
            if process.wasCancelled || Task.isCancelled {
                finishCancelled(job)
            } else if exitCode == 0 {
                switch job.source {
                case .youtube:
                    if let path = state.outputFile {
                        job.outputURL = URL(fileURLWithPath: path)
                    }
                case .localFile(_, let output):
                    job.outputURL = output
                }
                job.progress = 1
                job.status = .done
            } else {
                job.status = .failed(state.lastError ?? "종료 코드 \(exitCode)")
            }
        } catch is CancellationError {
            finishCancelled(job)
        } catch {
            job.log = state.logLines
            job.status = .failed(error.localizedDescription)
        }
    }

    private static func finishCancelled(_ job: Job) {
        job.status = .cancelled
        job.progress = nil
        if case .localFile(_, let output) = job.source {
            // 중간에 멈춘 불완전한 결과 파일은 지운다.
            try? FileManager.default.removeItem(at: output)
        }
    }

    static func apply(_ event: ParseEvent, to job: Job) {
        guard job.status.isActive else { return }
        switch event {
        case .progress(let value):
            job.progress = value
            if case .youtube = job.source {
                // 다운로드가 끝나면 ffmpeg 변환 단계로 넘어간다.
                job.status = value >= 1 ? .converting : .running
            }
        case .title(let title):
            job.title = title
        case .outputFile(let path):
            job.outputURL = URL(fileURLWithPath: path)
        }
    }
}
