import Foundation

/// 곡마다 마지막으로 듣던 위치와, 앱을 다시 켰을 때 이어 들을 재생 대기열을 기억한다.
///
/// 곡은 '폴더 이름/파일 이름'으로 구별한다. 같은 iCloud 폴더를 쓰는 기기끼리도 같은 열쇠가 되고,
/// 앱을 다시 설치해 앱 폴더 경로가 바뀌어도 그대로 찾을 수 있다.
@MainActor
enum PlaybackMemory {
    /// 이보다 앞이면 처음부터 듣는 것과 같으므로 기억하지 않는다.
    static let minimumPosition: TimeInterval = 5
    /// 끝나기 이만큼 전보다 뒤면 다 들은 것으로 보고 다음에는 처음부터 재생한다.
    static let finishedMargin: TimeInterval = 10
    private static let maxEntries = 500

    private static let positionsKey = "playback.positions"
    private static let sessionKey = "playback.session"

    private struct Entry: Codable {
        var time: TimeInterval
        var date: Date
    }

    static func key(for url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
    }

    // MARK: - 곡별 위치

    private static var positions: [String: Entry] = {
        guard let data = UserDefaults.standard.data(forKey: positionsKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// 이어 들을 위치 (없으면 nil = 처음부터)
    static func position(for url: URL) -> TimeInterval? {
        positions[key(for: url)]?.time
    }

    static func save(_ time: TimeInterval, duration: TimeInterval, for url: URL) {
        let key = key(for: url)
        let finished = duration > 0 && time >= duration - finishedMargin
        if !time.isFinite || time < minimumPosition || finished {
            guard positions[key] != nil else { return }
            positions[key] = nil
        } else {
            if let old = positions[key], abs(old.time - time) < 0.5 { return }
            positions[key] = Entry(time: time, date: Date())
            if positions.count > maxEntries {
                // 가장 오래전에 들은 곡부터 잊는다.
                let oldest = positions.sorted { $0.value.date < $1.value.date }.prefix(positions.count - maxEntries)
                for (key, _) in oldest { positions[key] = nil }
            }
        }
        persistPositions()
    }

    static func forget(_ url: URL) {
        guard positions.removeValue(forKey: key(for: url)) != nil else { return }
        persistPositions()
    }

    /// 파일 이름이 바뀌면 기억한 위치도 새 이름으로 옮긴다.
    static func moved(from old: URL, to new: URL) {
        guard let entry = positions.removeValue(forKey: key(for: old)) else { return }
        positions[key(for: new)] = entry
        persistPositions()
    }

    private static func persistPositions() {
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
    }

    // MARK: - 재생 대기열 (앱을 다시 켰을 때)

    struct Session: Codable {
        var queue: [String]
        var original: [String]
        var index: Int
        var shuffled: Bool
        var repeatMode: String
    }

    static func saveSession(_ session: Session?) {
        if let session, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
    }

    static func loadSession() -> Session? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }
}
