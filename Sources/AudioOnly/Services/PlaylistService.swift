import Foundation

struct PlaylistEntry: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let url: String?
    let duration: Double?
    let channel: String?
    let uploader: String?

    var displayTitle: String { title ?? id }

    var watchURL: String {
        if let url, url.hasPrefix("http") { return url }
        return "https://www.youtube.com/watch?v=\(id)"
    }

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct PlaylistInfo {
    let title: String
    let entries: [PlaylistEntry]
}

/// 형식이 맞지 않는 항목(삭제/비공개 영상 등)은 건너뛰기 위한 래퍼
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct RawPlaylist: Decodable {
    let id: String?
    let title: String?
    let url: String?
    let webpage_url: String?
    let duration: Double?
    let channel: String?
    let uploader: String?
    let entries: [Lossy<PlaylistEntry>]?
}

enum PlaylistError: LocalizedError {
    case missingYtDlp
    case failed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingYtDlp: return "yt-dlp를 찾을 수 없습니다. 설정에서 설치해 주세요."
        case .failed(let message): return message
        case .empty: return "재생목록에서 영상을 찾지 못했습니다."
        }
    }
}

enum PlaylistService {
    static func fetch(url: String, options: ExtractOptions) async throws -> PlaylistInfo {
        guard let ytDlp = options.ytDlpURL else { throw PlaylistError.missingYtDlp }

        let collector = LineCollector()
        let status = try await RunningProcess().run(
            executable: ytDlp,
            arguments: YTDLPCommand.playlistArguments(url: url, options: options),
            environment: ToolLocator.processEnvironment,
            onLine: { line, stream in collector.append(line, stream) }
        )
        guard status == 0 else {
            let message = collector.stderr.last(where: { $0.hasPrefix("ERROR:") }) ?? collector.stderr.last
            throw PlaylistError.failed(message ?? "yt-dlp 종료 코드 \(status)")
        }

        let json = collector.stdout.joined(separator: "\n")
        let raw: RawPlaylist
        do {
            raw = try JSONDecoder().decode(RawPlaylist.self, from: Data(json.utf8))
        } catch {
            throw PlaylistError.failed("재생목록 정보를 해석하지 못했습니다: \(error.localizedDescription)")
        }

        var entries = raw.entries?.compactMap(\.value) ?? []
        if raw.entries == nil, let id = raw.id {
            // 재생목록이 아닌 단일 영상 주소인 경우
            entries = [PlaylistEntry(
                id: id,
                title: raw.title,
                url: raw.webpage_url ?? raw.url,
                duration: raw.duration,
                channel: raw.channel,
                uploader: raw.uploader
            )]
        }
        guard !entries.isEmpty else { throw PlaylistError.empty }
        return PlaylistInfo(title: raw.title ?? "Playlist", entries: entries)
    }
}
