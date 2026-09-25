import Foundation
import YouTubeKit

enum JobUpdate: Sendable {
    case title(String)
    case downloading(Double, received: Int64, total: Int64)
    case converting(Double)
}

enum YouTubeError: LocalizedError {
    case invalidURL
    case noAudioStream
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "YouTube 주소를 인식하지 못했습니다."
        case .noAudioStream: return "내려받을 수 있는 오디오 스트림을 찾지 못했습니다."
        case .http(let code): return "다운로드 실패 (HTTP \(code))"
        }
    }
}

enum YouTubeLinks {
    /// watch?v=, youtu.be/, shorts/, embed/, live/, music.youtube.com, 또는 11자리 영상 ID
    static func videoID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoID(text) { return text }
        guard let components = URLComponents(string: text), let host = components.host?.lowercased() else {
            return nil
        }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(v) {
            return v
        }
        let parts = components.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be"), let first = parts.first, isVideoID(first) {
            return first
        }
        if host.contains("youtube"), parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]), isVideoID(parts[1]) {
            return parts[1]
        }
        return nil
    }

    static func isVideoID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

enum YouTubeAudioDownloader {
    /// 영상 1개의 오디오 스트림(m4a/AAC)을 내려받아 `directory`에 저장하고 최종 파일 URL을 반환한다.
    static func download(
        videoID: String,
        format: OutputFormat,
        embedArtwork: Bool,
        directory: URL,
        fileNamePrefix: String,
        update: @escaping @Sendable (JobUpdate) -> Void
    ) async throws -> URL {
        let video = YouTube(videoID: videoID)
        let streams = try await video.streams
        let audioOnly = streams.filterAudioOnly()
        guard let stream = audioOnly.filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream()
            ?? audioOnly.filter({ $0.isNativelyPlayable }).highestAudioBitrateStream()
        else {
            throw YouTubeError.noAudioStream
        }

        let metadata = try? await video.metadata
        let title = (metadata?.title).flatMap { $0.isEmpty ? nil : $0 } ?? videoID
        update(.title(title))

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Wi-Fi가 끊겨 멈췄던 경우 받은 부분부터 이어서 받는다.
        let partial = try await ChunkedDownloader.download(from: stream.url, key: videoID) { fraction, received, total in
            update(.downloading(fraction, received: received, total: total))
        }
        // 다 받았으면 AVFoundation이 알아보도록 .m4a 이름으로 바꾼다.
        let raw = FileStore.partialDownloadsDirectory.appendingPathComponent("\(videoID).m4a")
        try? fm.removeItem(at: raw)
        try fm.moveItem(at: partial, to: raw)
        defer { try? fm.removeItem(at: raw) }

        var artwork: Data?
        if embedArtwork, let thumbnailURL = metadata?.thumbnail?.url {
            artwork = try? await URLSession.shared.data(from: thumbnailURL).0
        }

        let output = NameReservations.shared.reserveUniqueURL(
            baseName: FileStore.sanitize(fileNamePrefix + title),
            fileExtension: format.fileExtension,
            in: directory
        )
        defer { NameReservations.shared.release(output) }

        update(.converting(0))
        switch format {
        case .m4a:
            // 재인코딩 없이 다시 담으면서 제목/앨범 아트를 넣는다. (DASH 조각 파일 → 일반 m4a)
            let items = AudioConverter.metadataItems(title: title, artist: nil, artwork: artwork)
            do {
                try await AudioConverter.exportM4A(from: raw, to: output, passthrough: true, metadata: items) {
                    update(.converting($0))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // 다시 담기에 실패하면 받은 파일을 그대로 쓴다.
                try? fm.removeItem(at: output)
                try fm.moveItem(at: raw, to: output)
            }
        case .wav:
            try await AudioConverter.exportWAV(from: raw, to: output) { update(.converting($0)) }
        }
        FileStore.removePartialDownloads(for: videoID)
        return output
    }
}

/// YouTube는 한 번에 큰 파일을 요청하면 속도를 제한하므로 Range 요청으로 나눠 받는다.
/// 받은 부분은 파일로 남겨 두었다가, 연결이 끊긴 뒤 다시 시작하면 이어서 받는다.
enum ChunkedDownloader {
    static let chunkSize: Int64 = 2 * 1024 * 1024

    /// 셀룰러 데이터를 쓰지 않는 세션. Wi-Fi가 끊기면 요청이 실패하고 작업은 'Wi-Fi 대기'가 된다.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    /// 받은(또는 이어받은) 파일 URL을 돌려준다. 파일은 Caches/PartialDownloads 에 남는다.
    static func download(
        from url: URL,
        key: String,
        progress: @escaping (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let directory = FileStore.partialDownloadsDirectory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var fileURL: URL?
        var total: Int64?
        var offset: Int64 = 0
        var handle: FileHandle?
        defer { try? handle?.close() }

        if let partial = FileStore.partialDownload(for: key) {
            let size = (try? fm.attributesOfItem(atPath: partial.url.path)[.size] as? NSNumber)?.int64Value ?? 0
            fileURL = partial.url
            total = partial.total > 0 ? partial.total : nil
            offset = size
            if let total, offset >= total {
                progress(1, offset, total)
                return partial.url
            }
            handle = try FileHandle(forWritingTo: partial.url)
            try handle?.seekToEnd()
            if let total { progress(Double(offset) / Double(total), offset, total) }
        }

        while true {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.setValue("bytes=\(offset)-\(offset + chunkSize - 1)", forHTTPHeaderField: "Range")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw YouTubeError.http(-1) }
            if http.statusCode == 416, let fileURL {
                return fileURL // 이미 끝까지 받음
            }
            guard (200...299).contains(http.statusCode) else { throw YouTubeError.http(http.statusCode) }

            let reportedTotal: Int64? = http.statusCode == 200
                ? Int64(data.count) // 서버가 Range를 무시하고 전체를 보냄
                : parseTotal(http.value(forHTTPHeaderField: "Content-Range"))

            // 이어받기가 거부됐거나 원본 크기가 달라졌으면 처음부터 다시 받는다.
            let restartNeeded = (http.statusCode == 200 && offset > 0)
                || (total != nil && reportedTotal != nil && reportedTotal != total)
            if restartNeeded {
                try? handle?.close()
                handle = nil
                if let fileURL { try? fm.removeItem(at: fileURL) }
                fileURL = nil
                total = nil
                offset = 0
                if http.statusCode != 200 { continue }
            }

            if fileURL == nil {
                total = reportedTotal
                let newURL = directory.appendingPathComponent("\(key)-\(reportedTotal ?? 0).part")
                fm.createFile(atPath: newURL.path, contents: nil)
                handle = try FileHandle(forWritingTo: newURL)
                fileURL = newURL
            }

            try handle?.write(contentsOf: data)
            offset += Int64(data.count)
            if let total, total > 0 {
                progress(min(Double(offset) / Double(total), 1), offset, total)
            }

            let finished = http.statusCode == 200
                || data.isEmpty
                || Int64(data.count) < chunkSize
                || (total.map { offset >= $0 } ?? false)
            if finished { break }
        }

        guard let fileURL else { throw YouTubeError.http(-1) }
        progress(1, offset, total ?? offset)
        return fileURL
    }

    /// "bytes 0-2097151/12345678" → 12345678
    private static func parseTotal(_ contentRange: String?) -> Int64? {
        guard let contentRange, let slash = contentRange.lastIndex(of: "/") else { return nil }
        return Int64(contentRange[contentRange.index(after: slash)...])
    }
}
