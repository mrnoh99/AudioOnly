import Foundation

extension Notification.Name {
    /// iCloud 파일을 기기로 다 받았을 때 (object: 파일 URL)
    static let cloudFileDownloaded = Notification.Name("AudioOnly.cloudFileDownloaded")
}

/// iCloud Drive 파일이 기기에 내려받아져 있는지 확인하는 도구
enum CloudFiles {
    /// 내용이 기기에 없어 재생하려면 iCloud에서 받아야 하는 파일인지
    static func needsDownload(_ url: URL) -> Bool {
        let fm = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true {
            return values.ubiquitousItemDownloadingStatus == .notDownloaded
        }
        // 예전 방식: 받지 않은 파일은 ".이름.icloud" 자리표시자만 있다.
        return !fm.fileExists(atPath: url.path) && fm.fileExists(atPath: placeholderURL(for: url).path)
    }

    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    /// ".노래.m4a.icloud" → "노래.m4a"
    static func realURL(forPlaceholder url: URL) -> URL? {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        let realName = String(name.dropFirst().dropLast(".icloud".count))
        return url.deletingLastPathComponent().appendingPathComponent(realName)
    }

    /// 받는 중인 파일이 기기에 얼마나 채워졌는지(대략). 알 수 없으면 nil.
    static func downloadProgress(_ url: URL) -> Double? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]),
              let size = values.fileSize, size > 0
        else { return nil }
        let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        // 0이면 '아직 모름'으로 본다(가만히 있는 0% 막대 대신 움직이는 막대를 보여 주기 위해).
        guard allocated > 0 else { return nil }
        return min(Double(allocated) / Double(size), 0.99)
    }

    static func fileSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        let size = values?.fileSize ?? values?.totalFileSize
        return size.flatMap { $0 > 0 ? Int64($0) : nil }
    }

    static func downloadError(_ url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
        return values?.ubiquitousItemDownloadingError?.localizedDescription
    }
}

/// iCloud에만 있는 파일을 Wi-Fi에서 기기로 받아 오고 진행 상황을 알려 준다.
///
/// 진행률은 iCloud 메타데이터(NSMetadataQuery의 '받은 비율')에서 읽는다.
/// iCloud가 비율을 알려 주지 않는 폴더면 움직이는 막대 + 경과 시간 + 파일 크기로 대신 보여 준다.
@MainActor
final class CloudDownloadManager: ObservableObject {
    static let shared = CloudDownloadManager()

    enum State: Equatable {
        /// Wi-Fi가 아니어서 기다리는 중
        case waitingForWiFi
        /// 받는 중 (진행률을 알 수 없으면 nil)
        case downloading(Double?)
        case failed(String)
    }

    @Published private(set) var states: [URL: State] = [:]
    private var pollTask: Task<Void, Never>?
    private var startedAt: [URL: Date] = [:]
    private var sizes: [URL: Int64] = [:]
    /// iCloud 메타데이터에서 읽은 받은 비율(0…1)
    private var reportedPercent: [URL: Double] = [:]
    /// 재생하려는 곡처럼 바로 필요한 파일. 이 파일들만 파일 조정자로 '다 받을 때까지 기다리기'를 한다.
    private var priority: Set<URL> = []
    /// 파일 조정자 읽기는 받을 때까지 스레드를 붙잡고 있으므로 동시에 2개까지만 한다.
    /// (자동 받기로 수십 개를 한꺼번에 기다리면 스레드가 고갈되고, 앱이 백그라운드로 갈 때
    /// 시스템이 한꺼번에 취소한다 — grantAccessClaim … Code=3072)
    private let coordinationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        queue.name = "AudioOnly.CloudCoordination"
        return queue
    }()
    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []

    func state(for url: URL) -> State? {
        states[url.standardizedFileURL]
    }

    /// 받기 시작한 시각(경과 시간 표시용)
    func startDate(for url: URL) -> Date? {
        startedAt[url.standardizedFileURL]
    }

    /// 파일 전체 크기(알 수 있으면)
    func size(for url: URL) -> Int64? {
        sizes[url.standardizedFileURL]
    }

    /// 받아 달라고 요청. Wi-Fi면 바로, 아니면 Wi-Fi에 연결될 때 시작한다.
    /// `priority`: 지금 재생하려는 곡처럼 바로 필요한 파일(다 받는 순간을 곧바로 알아챈다).
    func request(_ urls: [URL], priority isPriority: Bool = false) {
        for raw in urls {
            let url = raw.standardizedFileURL
            guard CloudFiles.needsDownload(url) else { continue }
            if isPriority && !priority.contains(url) {
                priority.insert(url)
                // 이미 받는 중이면 기다리기만 추가한다.
                if case .downloading? = states[url] { coordinateRead(url) }
            }
            switch states[url] {
            case .downloading?, .waitingForWiFi?:
                continue
            case .failed?, nil:
                states[url] = .waitingForWiFi
                if let size = CloudFiles.fileSize(url) { sizes[url] = size }
            }
        }
        startWaitingIfPossible()
    }

    func cancel(_ url: URL) {
        let key = url.standardizedFileURL
        states[key] = nil
        priority.remove(key)
        startedAt[key] = nil
        reportedPercent[key] = nil
        updateQuery()
    }

    var waitingCount: Int {
        states.values.filter { $0 == .waitingForWiFi }.count
    }

    var downloadingCount: Int {
        states.values.filter { if case .downloading = $0 { return true } else { return false } }.count
    }

    /// 받는 중인 파일들의 평균 진행률 (하나라도 모르면 nil)
    var averageProgress: Double? {
        var values: [Double] = []
        for state in states.values {
            guard case .downloading(let p) = state else { continue }
            guard let p else { return nil }
            values.append(p)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 네트워크가 바뀌면 AppModel이 알려 준다.
    func networkChanged() {
        startWaitingIfPossible()
    }

    private func startWaitingIfPossible() {
        guard NetworkMonitor.shared.state.allowsDownload else { return }
        for (url, state) in states where state == .waitingForWiFi {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                states[url] = .downloading(nil)
                startedAt[url] = Date()
                if priority.contains(url) { coordinateRead(url) }
            } catch {
                states[url] = .failed(error.localizedDescription)
            }
        }
        updateQuery()
        ensurePolling()
    }

    /// 파일 조정자로 읽기를 요청하면 시스템이 파일을 끝까지 받아 온 뒤 돌려준다.
    /// 상태 값이 늦게 바뀌어도 '다 받음'을 바로 알 수 있다.
    private func coordinateRead(_ url: URL) {
        coordinationQueue.addOperation {
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { _ in }
            // 취소(앱이 백그라운드로 가는 등)는 실패가 아니다 — 받기는 계속되고 주기적 확인이 끝을 알아챈다.
            let cancelled = error.map { $0.domain == NSCocoaErrorDomain && $0.code == NSUserCancelledError } ?? false
            let failed = cancelled ? nil : error?.localizedDescription
            Task { @MainActor in
                CloudDownloadManager.shared.coordinatedReadFinished(url, error: failed)
            }
        }
    }

    private func coordinatedReadFinished(_ url: URL, error: String?) {
        guard case .downloading = states[url] else { return }
        if let error, CloudFiles.needsDownload(url) {
            priority.remove(url)
            states[url] = .failed(error)
        } else if !CloudFiles.needsDownload(url) {
            finish(url)
        }
    }

    private func finish(_ url: URL) {
        priority.remove(url)
        states[url] = nil
        startedAt[url] = nil
        reportedPercent[url] = nil
        updateQuery()
        NotificationCenter.default.post(name: .cloudFileDownloaded, object: url)
    }

    // MARK: - iCloud 메타데이터로 진행률 읽기

    private func updateQuery() {
        let paths = states.compactMap { url, state -> String? in
            if case .downloading = state { return url.path }
            return nil
        }
        query?.stop()
        for observer in queryObservers { NotificationCenter.default.removeObserver(observer) }
        queryObservers = []
        query = nil
        guard !paths.isEmpty else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope,
        ]
        let names = paths.map { ($0 as NSString).lastPathComponent }
        query.predicate = NSPredicate(format: "%K IN %@", NSMetadataItemFSNameKey, names)
        query.valueListAttributes = [NSMetadataUbiquitousItemPercentDownloadedKey]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            queryObservers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.readQueryResults() }
            })
        }
        self.query = query
        query.start()
    }

    private func readQueryResults() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let wanted = Dictionary(uniqueKeysWithValues: states.keys.map { ($0.path, $0) })
        for case let item as NSMetadataItem in query.results {
            guard let path = (item.value(forAttribute: NSMetadataItemURLKey) as? URL)?.standardizedFileURL.path
                ?? item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let url = wanted[path]
            else { continue }
            if let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
                reportedPercent[url] = min(max(percent / 100, 0), 1)
                if case .downloading = states[url], states[url] != .downloading(reportedPercent[url]) {
                    states[url] = .downloading(reportedPercent[url])
                }
            }
        }
    }

    // MARK: - 상태 확인

    private func ensurePolling() {
        guard pollTask == nil, downloadingCount > 0 else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.poll() else { break }
                // 받는 파일이 많으면 조금 느긋하게 확인한다.
                try? await Task.sleep(for: .milliseconds(self.downloadingCount > 5 ? 1500 : 500))
            }
            self?.pollTask = nil
        }
    }

    /// 진행 상황을 갱신한다. 아직 받는 중인 파일이 있으면 true.
    private func poll() -> Bool {
        var active = false
        for (url, state) in states {
            guard case .downloading = state else { continue }
            if !CloudFiles.needsDownload(url) {
                finish(url)
            } else if let error = CloudFiles.downloadError(url) {
                priority.remove(url)
                states[url] = .failed(error)
            } else {
                // iCloud가 알려 준 비율을 우선 쓰고, 없으면 기기에 채워진 크기로 추정한다.
                let progress = reportedPercent[url] ?? CloudFiles.downloadProgress(url)
                // 값이 같으면 쓰지 않는다(@Published는 같은 값을 넣어도 화면을 다시 그리게 한다).
                if states[url] != .downloading(progress) { states[url] = .downloading(progress) }
                active = true
            }
        }
        return active
    }
}
