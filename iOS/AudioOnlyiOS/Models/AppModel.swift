import SwiftUI
import UIKit

enum AppTab: Hashable {
    case url, playlist, files, library, settings
}

enum JobSource {
    case youtube(videoID: String, directory: URL, fileNamePrefix: String, playlistTitle: String?)
    case localFile(URL)
}

@MainActor
final class Job: ObservableObject, Identifiable {
    enum Status: Equatable {
        case pending, downloading, converting, done, failed(String), cancelled

        var isActive: Bool { self == .downloading || self == .converting }

        var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            case .pending, .downloading, .converting: return false
            }
        }
    }

    let id = UUID()
    let source: JobSource
    let format: OutputFormat
    let embedArtwork: Bool

    @Published var title: String
    @Published var status: Status = .pending {
        didSet {
            if oldValue != status { onStatusChange?() }
        }
    }
    /// 상태가 바뀌면 AppModel이 사이드바·배지 등을 다시 그리도록 알린다.
    var onStatusChange: (() -> Void)?
    @Published var progress: Double?
    @Published var outputURL: URL?

    var task: Task<Void, Never>?

    init(source: JobSource, format: OutputFormat, embedArtwork: Bool, title: String) {
        self.source = source
        self.format = format
        self.embedArtwork = embedArtwork
        self.title = title
    }

    var subtitle: String {
        switch source {
        case .youtube(let videoID, _, _, let playlist):
            return playlist.map { "재생목록: \($0)" } ?? "youtu.be/\(videoID)"
        case .localFile(let url):
            return url.lastPathComponent
        }
    }

    var statusText: String {
        switch status {
        case .pending: return "대기 중"
        case .downloading:
            return progress.map { String(format: "다운로드 %.0f%%", $0 * 100) } ?? "다운로드 중"
        case .converting:
            return progress.map { String(format: "변환 %.0f%%", $0 * 100) } ?? "변환 중"
        case .done: return "완료"
        case .failed(let reason): return "실패: \(reason)"
        case .cancelled: return "취소됨"
        }
    }

    func apply(_ update: JobUpdate) {
        guard status.isActive else { return }
        switch update {
        case .title(let newTitle):
            title = newTitle
        case .downloading(let value):
            status = .downloading
            progress = value
        case .converting(let value):
            status = .converting
            progress = value
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let format = "format"
        static let embedArtwork = "embedArtwork"
        static let playlistSubfolder = "playlistSubfolder"
        static let playlistNumbering = "playlistNumbering"
        static let maxConcurrent = "maxConcurrent"
    }

    private let defaults = UserDefaults.standard

    @Published var selectedTab: AppTab = .url
    @Published var format: OutputFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    @Published var embedArtwork: Bool {
        didSet { defaults.set(embedArtwork, forKey: Keys.embedArtwork) }
    }
    @Published var playlistSubfolder: Bool {
        didSet { defaults.set(playlistSubfolder, forKey: Keys.playlistSubfolder) }
    }
    @Published var playlistNumbering: Bool {
        didSet { defaults.set(playlistNumbering, forKey: Keys.playlistNumbering) }
    }
    @Published var maxConcurrent: Int {
        didSet {
            defaults.set(maxConcurrent, forKey: Keys.maxConcurrent)
            pump()
        }
    }

    /// '파일' 탭에서 추출을 기다리는 로컬 파일(임시 복사본)
    @Published var pendingFiles: [URL] = []
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var library: [LibraryItem] = []
    @Published var importError: String?

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        let d = UserDefaults.standard
        format = OutputFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .m4a
        embedArtwork = d.object(forKey: Keys.embedArtwork) as? Bool ?? true
        playlistSubfolder = d.object(forKey: Keys.playlistSubfolder) as? Bool ?? true
        playlistNumbering = d.object(forKey: Keys.playlistNumbering) as? Bool ?? true
        let stored = d.integer(forKey: Keys.maxConcurrent)
        maxConcurrent = (1...4).contains(stored) ? stored : 2
        refreshLibrary()
    }

    var activeJobCount: Int {
        jobs.filter { !$0.status.isFinished }.count
    }

    // MARK: - 작업 추가

    func enqueueVideos(_ videos: [(id: String, title: String, number: Int?)], playlistTitle: String? = nil) {
        var directory = FileStore.documents
        if let playlistTitle, playlistSubfolder {
            directory.appendPathComponent(FileStore.sanitize(playlistTitle), isDirectory: true)
        }
        let newJobs = videos.map { video -> Job in
            var prefix = ""
            if let number = video.number, playlistNumbering {
                prefix = String(format: "%03d - ", number)
            }
            return Job(
                source: .youtube(videoID: video.id, directory: directory, fileNamePrefix: prefix, playlistTitle: playlistTitle),
                format: format,
                embedArtwork: embedArtwork,
                title: video.title
            )
        }
        enqueue(newJobs)
    }

    func enqueueLocalFiles(_ files: [URL]) {
        let newJobs = files.map {
            Job(source: .localFile($0), format: format, embedArtwork: false, title: $0.deletingPathExtension().lastPathComponent)
        }
        pendingFiles.removeAll { files.contains($0) }
        enqueue(newJobs)
    }

    private func enqueue(_ newJobs: [Job]) {
        guard !newJobs.isEmpty else { return }
        for job in newJobs {
            job.onStatusChange = { [weak self] in self?.objectWillChange.send() }
        }
        jobs.insert(contentsOf: newJobs, at: 0)
        pump()
    }

    // MARK: - 로컬 파일 가져오기

    func importFiles(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                pendingFiles.append(try FileStore.importCopy(of: url))
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        importError = failures.isEmpty ? nil : "가져오지 못한 파일: \(failures.joined(separator: ", "))"
    }

    func addImportedFile(_ url: URL) {
        pendingFiles.append(url)
    }

    func removePendingFiles(at offsets: IndexSet) {
        for index in offsets {
            FileStore.removeTemporaryImport(pendingFiles[index])
        }
        pendingFiles.remove(atOffsets: offsets)
    }

    /// 다른 앱에서 '공유 → AudioOnly' 또는 '다음으로 열기'로 받은 파일
    func handleOpenURL(_ url: URL) {
        guard url.isFileURL else { return }
        importFiles([url])
        selectedTab = .files
    }

    // MARK: - 작업 제어

    func cancel(_ job: Job) {
        switch job.status {
        case .pending: job.status = .cancelled
        case .downloading, .converting: job.task?.cancel()
        case .done, .failed, .cancelled: break
        }
    }

    func retry(_ job: Job) {
        guard job.status.isFinished, job.status != .done else { return }
        job.status = .pending
        job.progress = nil
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
        // 먼저 추가한 작업부터 (목록은 최신이 위)
        for job in jobs.reversed() where job.status == .pending {
            guard running < maxConcurrent else { break }
            running += 1
            start(job)
        }
        updateBackgroundState()
    }

    private func start(_ job: Job) {
        job.status = .downloading
        job.progress = nil
        job.task = Task { [weak self] in
            await JobRunner.run(job)
            job.task = nil
            self?.refreshLibrary()
            self?.pump()
        }
    }

    /// 작업 중에는 화면이 꺼지지 않게 하고, 앱이 백그라운드로 가도 잠시 더 실행되도록 요청한다.
    private func updateBackgroundState() {
        let busy = jobs.contains { $0.status.isActive }
        UIApplication.shared.isIdleTimerDisabled = busy
        if busy && backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AudioOnly") { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
        } else if !busy {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - 보관함

    func refreshLibrary() {
        library = FileStore.libraryItems()
    }

    func delete(_ items: [LibraryItem]) {
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
        }
        // 비어 있는 재생목록 폴더 정리
        for folder in Set(items.compactMap(\.folder)) {
            let url = FileStore.documents.appendingPathComponent(folder, isDirectory: true)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path), contents.isEmpty {
                try? FileManager.default.removeItem(at: url)
            }
        }
        refreshLibrary()
    }
}

@MainActor
enum JobRunner {
    static func run(_ job: Job) async {
        let update: @Sendable (JobUpdate) -> Void = { value in
            Task { @MainActor in job.apply(value) }
        }
        do {
            let output: URL
            switch job.source {
            case .youtube(let videoID, let directory, let prefix, _):
                output = try await YouTubeAudioDownloader.download(
                    videoID: videoID,
                    format: job.format,
                    embedArtwork: job.embedArtwork,
                    directory: directory,
                    fileNamePrefix: prefix,
                    update: update
                )
            case .localFile(let input):
                job.status = .converting
                output = try await extractLocal(input: input, format: job.format, update: update)
                FileStore.removeTemporaryImport(input)
            }
            job.outputURL = output
            job.progress = 1
            job.status = .done
        } catch {
            if Task.isCancelled || error is CancellationError {
                job.status = .cancelled
            } else {
                job.status = .failed(error.localizedDescription)
            }
            job.progress = nil
        }
    }

    private static func extractLocal(
        input: URL,
        format: OutputFormat,
        update: @escaping @Sendable (JobUpdate) -> Void
    ) async throws -> URL {
        let output = NameReservations.shared.reserveUniqueURL(
            baseName: FileStore.sanitize(input.deletingPathExtension().lastPathComponent),
            fileExtension: format.fileExtension,
            in: FileStore.documents
        )
        defer { NameReservations.shared.release(output) }
        switch format {
        case .m4a:
            try await AudioConverter.exportM4A(from: input, to: output) { update(.converting($0)) }
        case .wav:
            try await AudioConverter.exportWAV(from: input, to: output) { update(.converting($0)) }
        }
        return output
    }
}
