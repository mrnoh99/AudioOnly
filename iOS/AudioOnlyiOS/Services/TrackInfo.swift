import AVFoundation
import UIKit

/// 오디오 파일에 들어 있는 제목·아티스트·앨범 아트·길이
struct TrackInfo: @unchecked Sendable {
    var title: String?
    var artist: String?
    var artwork: UIImage?
    var duration: TimeInterval

    static let empty = TrackInfo(title: nil, artist: nil, artwork: nil, duration: 0)
}

/// 파일 메타데이터를 한 번만 읽어 두는 캐시
@MainActor
final class TrackInfoCache {
    static let shared = TrackInfoCache()

    private var cache: [URL: TrackInfo] = [:]
    private var loading: [URL: Task<TrackInfo, Never>] = [:]

    func cached(_ url: URL) -> TrackInfo? {
        cache[url]
    }

    func info(for url: URL) async -> TrackInfo {
        if let hit = cache[url] { return hit }
        if let running = loading[url] { return await running.value }
        let task = Task.detached(priority: .utility) { await Self.load(url) }
        loading[url] = task
        let result = await task.value
        cache[url] = result
        loading[url] = nil
        return result
    }

    func invalidate(_ urls: [URL]) {
        for url in urls { cache[url] = nil }
    }

    nonisolated private static func load(_ url: URL) async -> TrackInfo {
        let asset = AVURLAsset(url: url)
        var info = TrackInfo.empty
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            info.duration = seconds
        }
        guard let items = try? await asset.load(.commonMetadata) else { return info }
        for item in items {
            switch item.commonKey {
            case .commonKeyTitle?:
                info.title = try? await item.load(.stringValue)
            case .commonKeyArtist?:
                info.artist = try? await item.load(.stringValue)
            case .commonKeyArtwork?:
                if let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                    // 너무 큰 이미지는 비율을 유지한 채 줄여 둔다.
                    let scale = min(1, 800 / max(image.size.width, image.size.height, 1))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    info.artwork = image.preparingThumbnail(of: size) ?? image
                }
            default:
                break
            }
        }
        if info.title?.isEmpty == true { info.title = nil }
        if info.artist?.isEmpty == true { info.artist = nil }
        return info
    }
}
