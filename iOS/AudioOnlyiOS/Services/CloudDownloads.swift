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
        return min(Double(allocated) / Double(size), 0.99)
    }

    static func downloadError(_ url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
        return values?.ubiquitousItemDownloadingError?.localizedDescription
    }
}

/// iCloud에만 있는 파일을 Wi-Fi에서 기기로 받아 오고 진행 상황을 알려 준다.
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

    func state(for url: URL) -> State? {
        states[url.standardizedFileURL]
    }

    /// 받아 달라고 요청. Wi-Fi면 바로, 아니면 Wi-Fi에 연결될 때 시작한다.
    func request(_ urls: [URL]) {
        for raw in urls {
            let url = raw.standardizedFileURL
            guard CloudFiles.needsDownload(url) else { continue }
            switch states[url] {
            case .downloading?, .waitingForWiFi?:
                continue
            case .failed?, nil:
                states[url] = .waitingForWiFi
            }
        }
        startWaitingIfPossible()
    }

    func cancel(_ url: URL) {
        states[url.standardizedFileURL] = nil
    }

    var waitingCount: Int {
        states.values.filter { $0 == .waitingForWiFi }.count
    }

    var downloadingCount: Int {
        states.values.filter { if case .downloading = $0 { return true } else { return false } }.count
    }

    /// 받는 중인 파일들의 평균 진행률
    var averageProgress: Double? {
        let values = states.values.compactMap { state -> Double? in
            if case .downloading(let p) = state { return p ?? 0 }
            return nil
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
            } catch {
                states[url] = .failed(error.localizedDescription)
            }
        }
        ensurePolling()
    }

    private func ensurePolling() {
        guard pollTask == nil, states.values.contains(where: { if case .downloading = $0 { return true } else { return false } })
        else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.poll() else { break }
                try? await Task.sleep(for: .milliseconds(500))
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
                states[url] = nil
                startedAt[url] = nil
                NotificationCenter.default.post(name: .cloudFileDownloaded, object: url)
            } else if let error = CloudFiles.downloadError(url) {
                states[url] = .failed(error)
            } else {
                states[url] = .downloading(CloudFiles.downloadProgress(url))
                active = true
            }
        }
        return active
    }
}
