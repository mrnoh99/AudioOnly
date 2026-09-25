import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

enum RepeatMode: CaseIterable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String { self == .one ? "repeat.1" : "repeat" }
}

/// 잠자기 타이머 선택지
enum SleepTimerOption: Hashable, Identifiable {
    case minutes(Int)
    case endOfTrack

    static let all: [SleepTimerOption] = [
        .minutes(5), .minutes(10), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .minutes(90), .endOfTrack,
    ]

    var id: String { title }

    var title: String {
        switch self {
        case .minutes(let m) where m >= 60 && m % 60 == 0: return "\(m / 60)시간"
        case .minutes(let m) where m >= 60: return "\(m / 60)시간 \(m % 60)분"
        case .minutes(let m): return "\(m)분"
        case .endOfTrack: return "현재 곡이 끝나면"
        }
    }
}

/// 음악 앱처럼 동작하는 재생기: 재생 대기열, 셔플/반복, 잠자기 타이머(서서히 줄어들며 정지),
/// 백그라운드 재생, 잠금 화면·제어 센터 조작.
@MainActor
final class AudioPlayer: ObservableObject {
    static let fadeDuration: TimeInterval = 10
    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    /// 실제 재생 순서(셔플이면 섞인 순서)
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var info = TrackInfo.empty
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var rate: Float = 1.0
    @Published var showNowPlaying = false

    /// 현재 곡이 iCloud에만 있어 받는 중(또는 Wi-Fi 대기)
    @Published private(set) var isWaitingForCloud = false
    /// 받기가 끝나면 바로 재생할지
    private var playWhenDownloaded = false
    private var cloudObserver: NSObjectProtocol?

    @Published private(set) var sleepTimerEnd: Date?
    @Published private(set) var sleepAtEndOfTrack = false
    @Published private(set) var isFadingOut = false

    private let player = AVPlayer()
    /// 셔플을 끌 때 되돌아갈 원래 순서
    private var originalQueue: [LibraryItem] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []
    private var sleepTask: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observeAudioSession()
        configureRemoteCommands()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: .cloudFileDownloaded, object: nil, queue: .main
        ) { [weak self] note in
            let url = note.object as? URL
            MainActor.assumeIsolated {
                guard let self, self.isWaitingForCloud, let url, url == self.current?.url.standardizedFileURL else { return }
                self.isWaitingForCloud = false
                self.loadCurrent(autoplay: self.playWhenDownloaded)
            }
        }
    }

    // MARK: - 상태

    var current: LibraryItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    /// 다음에 재생될 곡들
    var upNext: [LibraryItem] {
        guard index + 1 < queue.count else { return [] }
        return Array(queue[(index + 1)...])
    }

    /// 화면에 보이는 제목은 파일 이름(사용자가 바꾼 이름이 그대로 보이도록)
    var title: String { current?.name ?? info.title ?? "" }
    var subtitle: String { info.artist ?? current?.folder ?? "AudioOnly" }

    // MARK: - 재생 시작

    /// 목록을 재생 대기열로 만들고 `startAt` 곡부터 재생한다.
    func play(_ items: [LibraryItem], startAt start: LibraryItem? = nil, shuffle: Bool = false) {
        guard !items.isEmpty else { return }
        originalQueue = items
        isShuffled = shuffle
        if shuffle {
            var shuffled = items.shuffled()
            if let start, let i = shuffled.firstIndex(of: start) {
                shuffled.swapAt(0, i)
            }
            queue = shuffled
            index = 0
        } else {
            queue = items
            index = start.flatMap { items.firstIndex(of: $0) } ?? 0
        }
        loadCurrent(autoplay: true)
    }

    /// 목록의 한 곡을 누른 경우: 이미 재생 중인 곡이면 재생/일시정지 전환
    func select(_ item: LibraryItem, in items: [LibraryItem]) {
        if current == item {
            togglePlayPause()
        } else {
            play(items, startAt: item, shuffle: false)
        }
    }

    func playNext(_ item: LibraryItem) {
        guard current != nil else {
            play([item])
            return
        }
        queue.insert(item, at: index + 1)
        originalQueue.append(item)
    }

    func playLater(_ item: LibraryItem) {
        guard current != nil else {
            play([item])
            return
        }
        queue.append(item)
        originalQueue.append(item)
    }

    // MARK: - 조작

    func togglePlayPause() {
        if isFadingOut {
            // 타이머로 소리가 줄어드는 중에 누르면 타이머를 취소하고 계속 듣는다.
            cancelSleepTimer()
            return
        }
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard let item = current else { return }
        if isWaitingForCloud {
            // 아직 iCloud에서 받는 중: 다 받으면 재생
            playWhenDownloaded = true
            CloudDownloadManager.shared.request([item.url])
            return
        }
        activateSession()
        if player.currentItem == nil { loadCurrent(autoplay: false) }
        player.volume = 1
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        playWhenDownloaded = false
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if index + 1 < queue.count {
            index += 1
            loadCurrent(autoplay: true)
        } else if repeatMode != .off {
            index = 0
            loadCurrent(autoplay: true)
        } else {
            // 대기열 끝: 음악 앱처럼 첫 곡으로 돌아가 멈춘다.
            index = 0
            loadCurrent(autoplay: false)
        }
    }

    /// 3초 이상 들었으면 곡 처음으로, 아니면 이전 곡으로
    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 || (index == 0 && repeatMode == .off) {
            seek(to: 0)
        } else {
            index = index > 0 ? index - 1 : queue.count - 1
            loadCurrent(autoplay: isPlaying)
        }
    }

    func jump(to item: LibraryItem) {
        guard let i = queue.firstIndex(of: item) else { return }
        index = i
        loadCurrent(autoplay: true)
    }

    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration > 0 ? duration : time))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player.rate = newRate }
        updateNowPlaying()
    }

    func toggleShuffle() {
        guard let now = current else {
            isShuffled.toggle()
            return
        }
        if isShuffled {
            queue = originalQueue
            index = originalQueue.firstIndex(of: now) ?? 0
        } else {
            queue = [now] + originalQueue.filter { $0 != now }.shuffled()
            index = 0
        }
        isShuffled.toggle()
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        var upcoming = upNext
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((index + 1)..., with: upcoming)
    }

    func removeUpNext(at offsets: IndexSet) {
        var upcoming = upNext
        let removed = offsets.map { upcoming[$0] }
        upcoming.remove(atOffsets: offsets)
        queue.replaceSubrange((index + 1)..., with: upcoming)
        for item in removed {
            if let i = originalQueue.firstIndex(of: item) { originalQueue.remove(at: i) }
        }
    }

    /// 보관함에서 파일 이름을 바꿨을 때 대기열의 항목도 새 경로로 바꾼다.
    /// 재생 중인 곡은 이미 열린 파일로 계속 재생된다.
    func itemRenamed(from old: LibraryItem, to new: LibraryItem) {
        queue = queue.map { $0 == old ? new : $0 }
        originalQueue = originalQueue.map { $0 == old ? new : $0 }
        if current == new { updateNowPlaying() }
    }

    /// 보관함에서 파일을 지웠을 때 대기열에서도 뺀다.
    func removeFromQueue(_ items: [LibraryItem]) {
        let removed = Set(items)
        if let now = current, removed.contains(now) {
            stop()
            return
        }
        let now = current
        queue.removeAll { removed.contains($0) }
        originalQueue.removeAll { removed.contains($0) }
        if let now, let i = queue.firstIndex(of: now) { index = i }
    }

    func stop() {
        cancelSleepTimer()
        isWaitingForCloud = false
        playWhenDownloaded = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        originalQueue = []
        index = 0
        isPlaying = false
        currentTime = 0
        duration = 0
        info = .empty
        showNowPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 잠자기 타이머

    func setSleepTimer(_ option: SleepTimerOption) {
        cancelSleepTimer()
        switch option {
        case .endOfTrack:
            sleepAtEndOfTrack = true
        case .minutes(let minutes):
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            sleepTimerEnd = end
            sleepTask = Task { [weak self] in
                let wait = max(0, end.timeIntervalSinceNow - Self.fadeDuration)
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                await self?.fadeOutAndPause(over: min(Self.fadeDuration, max(end.timeIntervalSinceNow, 1)))
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerEnd = nil
        sleepAtEndOfTrack = false
        if isFadingOut {
            isFadingOut = false
            player.volume = 1
        }
    }

    var isSleepTimerActive: Bool { sleepTimerEnd != nil || sleepAtEndOfTrack }

    /// 볼륨을 천천히 0으로 줄인 뒤 멈춘다. 갑자기 끊기지 않도록.
    private func fadeOutAndPause(over fade: TimeInterval) async {
        guard isPlaying else {
            finishSleepTimer()
            return
        }
        isFadingOut = true
        let steps = 50
        let startVolume = player.volume
        for step in 1...steps {
            guard !Task.isCancelled, isFadingOut else { return }
            // 귀에 자연스럽게 들리도록 곡선형으로 줄인다.
            let progress = Double(step) / Double(steps)
            player.volume = startVolume * Float(pow(1 - progress, 2))
            try? await Task.sleep(for: .seconds(fade / Double(steps)))
        }
        guard !Task.isCancelled, isFadingOut else { return }
        pause()
        player.volume = 1
        isFadingOut = false
        finishSleepTimer()
    }

    private func finishSleepTimer() {
        sleepTask = nil
        sleepTimerEnd = nil
        sleepAtEndOfTrack = false
    }

    // MARK: - 내부

    private func loadCurrent(autoplay: Bool) {
        guard let item = current else {
            stop()
            return
        }

        // iCloud에만 있는 곡: Wi-Fi에서 받은 뒤 재생한다(받는 동안 진행 상황 표시).
        if CloudFiles.needsDownload(item.url) {
            player.pause()
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            isWaitingForCloud = true
            playWhenDownloaded = autoplay
            currentTime = 0
            duration = 0
            info = TrackInfo(title: item.name, artist: item.folder, artwork: nil, duration: 0)
            CloudDownloadManager.shared.request([item.url])
            updateNowPlaying()
            return
        }
        isWaitingForCloud = false

        let playerItem = AVPlayerItem(url: item.url)
        playerItem.audioTimePitchAlgorithm = .timeDomain // 배속에서도 음정 유지

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidFinish() }
        }

        player.replaceCurrentItem(with: playerItem)
        currentTime = 0
        duration = 0
        info = TrackInfo(title: item.name, artist: item.folder, artwork: nil, duration: 0)

        Task { [weak self] in
            let loaded = await TrackInfoCache.shared.info(for: item.url)
            guard let self, self.current == item else { return }
            self.info = TrackInfo(
                title: loaded.title ?? item.name,
                artist: loaded.artist ?? item.folder,
                artwork: loaded.artwork,
                duration: loaded.duration
            )
            if self.duration == 0 { self.duration = loaded.duration }
            self.updateNowPlaying()
        }

        if autoplay {
            resume()
        } else {
            player.pause()
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func itemDidFinish() {
        if sleepAtEndOfTrack {
            pause()
            player.volume = 1
            isFadingOut = false
            finishSleepTimer()
            return
        }
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }

    private func tick(_ time: CMTime) {
        guard player.currentItem != nil else { return }
        let seconds = time.seconds
        if seconds.isFinite { currentTime = seconds }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        // '현재 곡이 끝나면' 타이머: 곡 끝 몇 초 전부터 서서히 줄인다.
        if sleepAtEndOfTrack, isPlaying, !isFadingOut, sleepTask == nil, duration > 0 {
            let remaining = duration - currentTime
            if remaining <= 5 {
                sleepTask = Task { [weak self] in
                    await self?.fadeOutAndPause(over: max(remaining, 0.5))
                }
            }
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // 전화 등으로 끊김
                    self.isPlaying = false
                    self.updateNowPlaying()
                case .ended:
                    if options.contains(.shouldResume) { self.resume() }
                default:
                    break
                }
            }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                // 이어폰을 빼면 스피커로 갑자기 나오지 않도록 멈춘다.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let item = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var nowPlaying: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let folder = item.folder {
            nowPlaying[MPMediaItemPropertyAlbumTitle] = folder
        }
        if let artwork = info.artwork {
            nowPlaying[MPMediaItemPropertyArtwork] = Self.makeArtwork(artwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
    }

    /// 잠금 화면이 다른 스레드에서 이미지를 요청하므로 메인 액터 밖에서 만든다.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
