import AVFoundation
import SwiftUI

/// 보관함에서 추출한 오디오를 바로 들어볼 수 있는 간단한 플레이어
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var current: LibraryItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(_ item: LibraryItem) {
        if current == item {
            toggle()
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: item.url)
            newPlayer.delegate = self
            newPlayer.play()
            player = newPlayer
            current = item
            duration = newPlayer.duration
            isPlaying = true
            startTimer()
        } catch {
            current = nil
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying = player.isPlaying
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        current = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
        }
    }
}
