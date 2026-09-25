import SwiftUI
import UIKit

enum AppTab: Hashable {
    case url, playlist, files, library, settings
}

enum JobSource {
    case youtube(videoID: String, directory: URL, fileNamePrefix: String, playlistTitle: String?)
    case localFile(URL, directory: URL)
}

@MainActor
final class Job: ObservableObject, Identifiable {
    enum Status: Equatable {
        case pending, waitingForWiFi, downloading, converting, done, failed(String), cancelled

        var isActive: Bool { self == .downloading || self == .converting }

        var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: return true
            case .pending, .waitingForWiFi, .downloading, .converting: return false
            }
        }
    }

    let id = UUID()
    let source: JobSource
    let format: OutputFormat
    let embedArtwork: Bool
    /// 재생목록 하위 폴더 이름(저장 위치 기준). 작업을 저장했다가 복원할 때 쓴다.
    let subfolder: String?

    @Published var title: String
    @Published var status: Status = .pending {
        didSet {
            if oldValue != status { onStatusChange?() }
        }
    }
    /// 상태가 바뀌면 AppModel이 사이드바·배지 등을 다시 그리도록 알린다.
    var onStatusChange: (() -> Void)?
    @Published var progress: Double? {
        didSet { onProgressChange?() }
    }
    /// 전체 진행 막대를 갱신하기 위한 알림
    var onProgressChange: (() -> Void)?
    /// "12.3 MB / 27.5 MB"
    @Published var bytesText: String?
    @Published var outputURL: URL?

    var task: Task<Void, Never>?
    /// Wi-Fi가 끊겨 앱이 일부러 멈춘 경우(취소가 아니라 'Wi-Fi 대기'로 돌린다)
    var pausedForNetwork = false
    var networkRetries = 0

    init(source: JobSource, format: OutputFormat, embedArtwork: Bool, title: String, subfolder: String? = nil) {
        self.source = source
        self.format = format
        self.embedArtwork = embedArtwork
        self.title = title
        self.subfolder = subfolder
    }

    var videoID: String? {
        if case .youtube(let id, _, _, _) = source { return id }
        return nil
    }

    /// 네트워크가 필요한 작업인지 (로컬 파일 추출은 Wi-Fi가 없어도 된다)
    var needsNetwork: Bool { videoID != nil }

    var subtitle: String {
        switch source {
        case .youtube(let videoID, _, _, let playlist):
            return playlist.map { "재생목록: \($0)" } ?? "youtu.be/\(videoID)"
        case .localFile(let url, _):
            return url.lastPathComponent
        }
    }

    var statusText: String {
        switch status {
        case .pending: return "대기 중"
        case .waitingForWiFi:
            if let progress, progress > 0 {
                return String(format: "Wi-Fi 연결을 기다리는 중 · %.0f%% 받음 (연결되면 이어서 받습니다)", progress * 100)
            }
            return "Wi-Fi 연결을 기다리는 중 (연결되면 자동으로 시작합니다)"
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
        case .downloading(let value, let received, let total):
            status = .downloading
            progress = value
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            bytesText = "\(formatter.string(fromByteCount: received)) / \(formatter.string(fromByteCount: total))"
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
        static let outputFolderBookmark = "outputFolderBookmark"
        static let savedJobs = "savedJobs"
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

    /// 사용자가 '파일' 앱에서 고른 저장 폴더. nil이면 앱의 기본 폴더(나의 iPad > AudioOnly)
    @Published private(set) var customOutputFolder: URL?
    @Published var outputFolderError: String?

    /// Wi-Fi 감시. YouTube 다운로드는 Wi-Fi에서만 진행한다.
    let network = NetworkMonitor()
    /// "Wi-Fi에 연결되었습니다 …" 같은 잠깐 보이는 안내
    @Published private(set) var networkNotice: String?
    private var noticeTask: Task<Void, Never>?

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        let d = UserDefaults.standard
        format = OutputFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .m4a
        embedArtwork = d.object(forKey: Keys.embedArtwork) as? Bool ?? true
        playlistSubfolder = d.object(forKey: Keys.playlistSubfolder) as? Bool ?? true
        playlistNumbering = d.object(forKey: Keys.playlistNumbering) as? Bool ?? true
        let stored = d.integer(forKey: Keys.maxConcurrent)
        maxConcurrent = (1...4).contains(stored) ? stored : 2
        restoreOutputFolder()
        refreshLibrary()
        network.onChange = { [weak self] old, new in
            self?.networkChanged(from: old, to: new)
        }
        restoreSavedJobs()
    }

    var activeJobCount: Int {
        jobs.filter { !$0.status.isFinished }.count
    }

    var waitingForWiFiCount: Int {
        jobs.filter { $0.status == .waitingForWiFi }.count
    }

    /// 전체 진행 상황(취소한 작업 제외)
    struct Summary {
        var total = 0
        var done = 0
        var running = 0
        var waiting = 0
        var queued = 0
        var failed = 0
        var fraction: Double = 0
    }

    var summary: Summary {
        var result = Summary()
        var sum = 0.0
        for job in jobs where job.status != .cancelled {
            result.total += 1
            switch job.status {
            case .done:
                result.done += 1
                sum += 1
            case .downloading, .converting:
                result.running += 1
                // 다운로드는 전체의 90%, 변환은 나머지 10%로 본다.
                let p = job.progress ?? 0
                sum += job.status == .converting ? 0.9 + 0.1 * p : 0.9 * p
            case .waitingForWiFi:
                result.waiting += 1
                sum += 0.9 * (job.progress ?? 0)
            case .pending:
                result.queued += 1
            case .failed:
                result.failed += 1
            case .cancelled:
                break
            }
        }
        result.fraction = result.total > 0 ? sum / Double(result.total) : 0
        return result
    }

    // MARK: - 저장 위치

    var outputDirectory: URL {
        customOutputFolder ?? FileStore.documents
    }

    var outputFolderDisplayName: String {
        customOutputFolder?.lastPathComponent ?? "\(UIDevice.localStorageName) › AudioOnly (기본)"
    }

    /// '파일' 앱 폴더 선택기에서 고른 폴더를 저장 위치로 쓴다.
    /// 보안 범위 북마크로 저장해 두어 앱을 다시 켜도 그 폴더에 계속 쓸 수 있다.
    func setOutputFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Keys.outputFolderBookmark)
            customOutputFolder = url
            outputFolderError = nil
            refreshLibrary()
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            outputFolderError = "이 폴더는 저장 위치로 쓸 수 없습니다: \(error.localizedDescription)"
        }
    }

    func resetOutputFolder() {
        // 진행 중인 작업이 쓰고 있을 수 있으므로 이전 폴더 접근 권한은 앱이 끝날 때까지 유지한다.
        defaults.removeObject(forKey: Keys.outputFolderBookmark)
        customOutputFolder = nil
        outputFolderError = nil
        refreshLibrary()
    }

    private func restoreOutputFolder() {
        guard let bookmark = defaults.data(forKey: Keys.outputFolderBookmark) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            defaults.removeObject(forKey: Keys.outputFolderBookmark)
            outputFolderError = "이전에 고른 저장 폴더를 찾을 수 없어 기본 폴더로 되돌렸습니다."
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Keys.outputFolderBookmark)
        }
        customOutputFolder = url
    }

    // MARK: - 작업 추가

    func enqueueVideos(_ videos: [(id: String, title: String, number: Int?)], playlistTitle: String? = nil) {
        var directory = outputDirectory
        var subfolder: String?
        if let playlistTitle, playlistSubfolder {
            subfolder = FileStore.sanitize(playlistTitle)
            directory.appendPathComponent(subfolder!, isDirectory: true)
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
                title: video.title,
                subfolder: subfolder
            )
        }
        enqueue(newJobs)
    }

    func enqueueLocalFiles(_ files: [URL]) {
        let directory = outputDirectory
        let newJobs = files.map {
            Job(
                source: .localFile($0, directory: directory),
                format: format,
                embedArtwork: false,
                title: $0.deletingPathExtension().lastPathComponent
            )
        }
        pendingFiles.removeAll { files.contains($0) }
        enqueue(newJobs)
    }

    private func enqueue(_ newJobs: [Job]) {
        guard !newJobs.isEmpty else { return }
        for job in newJobs {
            job.onStatusChange = { [weak self] in
                self?.objectWillChange.send()
                self?.saveJobs()
            }
            job.onProgressChange = { [weak self] in
                self?.objectWillChange.send()
            }
        }
        jobs.insert(contentsOf: newJobs, at: 0)
        pump()
        saveJobs()
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
        case .pending, .waitingForWiFi:
            job.status = .cancelled
            if let id = job.videoID { FileStore.removePartialDownloads(for: id) }
        case .downloading, .converting: job.task?.cancel()
        case .done, .failed, .cancelled: break
        }
    }

    func retry(_ job: Job) {
        guard job.status.isFinished, job.status != .done else { return }
        job.status = .pending
        job.progress = nil
        job.networkRetries = 0
        pump()
    }

    func remove(_ job: Job) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
        saveJobs()
    }

    func clearFinished() {
        jobs.removeAll { $0.status.isFinished }
        saveJobs()
    }

    private func pump() {
        var running = jobs.filter { $0.status.isActive }.count
        let canDownload = network.state.allowsDownload
        // 먼저 추가한 작업부터 (목록은 최신이 위)
        for job in jobs.reversed() where job.status == .pending {
            if job.needsNetwork && !canDownload {
                // Wi-Fi가 아니면 다운로드하지 않고 기다린다.
                if network.state != .unknown { job.status = .waitingForWiFi }
                continue
            }
            guard running < maxConcurrent else { continue }
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
            self?.retryAfterNetworkErrorIfPossible(job)
            self?.pump()
        }
    }

    // MARK: - Wi-Fi

    private func networkChanged(from old: NetworkState, to new: NetworkState) {
        objectWillChange.send()
        if new.allowsDownload {
            let waiting = jobs.filter { $0.status == .waitingForWiFi }
            for job in waiting { job.status = .pending }
            if !waiting.isEmpty {
                showNotice("Wi-Fi에 연결되었습니다. 기다리던 \(waiting.count)개 다운로드를 시작합니다.")
            }
        } else if new != .unknown {
            // 다운로드 중이던 작업은 멈추고 Wi-Fi를 기다린다. 받은 부분은 남겨 두었다가 이어서 받는다.
            var paused = 0
            for job in jobs where job.needsNetwork && job.status == .downloading {
                job.pausedForNetwork = true
                job.task?.cancel()
                paused += 1
            }
            if paused > 0 {
                showNotice("Wi-Fi 연결이 끊겨 다운로드 \(paused)개를 일시 중지했습니다. Wi-Fi에 다시 연결되면 이어서 받습니다.")
            }
        }
        pump()
    }

    /// 일시적인 네트워크 오류로 'Wi-Fi 대기'가 된 작업은 Wi-Fi라면 잠시 후 다시 시도한다.
    private func retryAfterNetworkErrorIfPossible(_ job: Job) {
        guard job.status == .waitingForWiFi, network.state.allowsDownload else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, job.status == .waitingForWiFi, self.network.state.allowsDownload else { return }
            job.status = .pending
            self.pump()
        }
    }

    private func showNotice(_ text: String) {
        networkNotice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.networkNotice = nil
        }
    }

    // MARK: - 작업 저장 (앱을 껐다 켜도 받지 못한 파일을 이어서 받는다)

    private struct SavedJob: Codable {
        var videoID: String
        var title: String
        var fileNamePrefix: String
        var playlistTitle: String?
        var subfolder: String?
        var format: String
        var embedArtwork: Bool
    }

    private func saveJobs() {
        let saved: [SavedJob] = jobs.compactMap { job in
            guard !job.status.isFinished,
                  case .youtube(let id, _, let prefix, let playlistTitle) = job.source
            else { return nil }
            return SavedJob(
                videoID: id,
                title: job.title,
                fileNamePrefix: prefix,
                playlistTitle: playlistTitle,
                subfolder: job.subfolder,
                format: job.format.rawValue,
                embedArtwork: job.embedArtwork
            )
        }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Keys.savedJobs)
        }
    }

    private func restoreSavedJobs() {
        guard let data = defaults.data(forKey: Keys.savedJobs),
              let saved = try? JSONDecoder().decode([SavedJob].self, from: data),
              !saved.isEmpty
        else { return }
        let restored = saved.map { item -> Job in
            var directory = outputDirectory
            if let subfolder = item.subfolder {
                directory.appendPathComponent(subfolder, isDirectory: true)
            }
            return Job(
                source: .youtube(
                    videoID: item.videoID,
                    directory: directory,
                    fileNamePrefix: item.fileNamePrefix,
                    playlistTitle: item.playlistTitle
                ),
                format: OutputFormat(rawValue: item.format) ?? .m4a,
                embedArtwork: item.embedArtwork,
                title: item.title,
                subfolder: item.subfolder
            )
        }
        // 저장 순서는 최신이 앞. enqueue는 앞에 끼워 넣으므로 그대로 넘긴다.
        enqueue(restored)
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
        library = FileStore.libraryItems(in: outputDirectory)
    }

    func delete(_ items: [LibraryItem]) {
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
        }
        // 비어 있는 재생목록 폴더 정리
        for folder in Set(items.compactMap(\.folder)) {
            let url = outputDirectory.appendingPathComponent(folder, isDirectory: true)
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
            case .localFile(let input, let directory):
                job.status = .converting
                output = try await extractLocal(input: input, directory: directory, format: job.format, update: update)
                FileStore.removeTemporaryImport(input)
            }
            job.outputURL = output
            job.progress = 1
            job.bytesText = nil
            job.networkRetries = 0
            job.status = .done
        } catch {
            if job.pausedForNetwork {
                // Wi-Fi가 끊겨 앱이 멈춘 경우: 받은 부분을 보존하고 기다린다.
                job.pausedForNetwork = false
                job.status = .waitingForWiFi
            } else if Task.isCancelled || error is CancellationError {
                job.status = .cancelled
                job.progress = nil
                if let id = job.videoID { FileStore.removePartialDownloads(for: id) }
            } else if job.needsNetwork, isNetworkError(error), job.networkRetries < 3 {
                job.networkRetries += 1
                job.status = .waitingForWiFi
            } else {
                job.status = .failed(error.localizedDescription)
                job.progress = nil
            }
        }
    }

    /// 연결이 끊기거나 셀룰러가 막혀서 난 오류인지
    private static func isNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
            .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .callIsActive,
        ]
        return codes.contains(urlError.code)
    }

    private static func extractLocal(
        input: URL,
        directory: URL,
        format: OutputFormat,
        update: @escaping @Sendable (JobUpdate) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = NameReservations.shared.reserveUniqueURL(
            baseName: FileStore.sanitize(input.deletingPathExtension().lastPathComponent),
            fileExtension: format.fileExtension,
            in: directory
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
