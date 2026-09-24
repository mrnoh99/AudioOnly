import Foundation
import YouTubeKit

enum JobUpdate: Sendable {
    case title(String)
    case downloading(Double)
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
        try fm.createDirectory(at: FileStore.downloadsTemporaryDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = FileStore.downloadsTemporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? fm.removeItem(at: raw) }

        try await ChunkedDownloader.download(from: stream.url, to: raw) { fraction in
            update(.downloading(fraction))
        }

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
        return output
    }
}

/// YouTube는 한 번에 큰 파일을 요청하면 속도를 제한하므로 Range 요청으로 나눠 받는다.
enum ChunkedDownloader {
    static let chunkSize = 2 * 1024 * 1024

    static func download(from url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        fm.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var offset = 0
        var total: Int?
        while true {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.setValue("bytes=\(offset)-\(offset + chunkSize - 1)", forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw YouTubeError.http(-1) }
            if http.statusCode == 416 { break } // 범위를 벗어남 = 끝까지 받음
            guard (200...299).contains(http.statusCode) else { throw YouTubeError.http(http.statusCode) }

            try handle.write(contentsOf: data)
            offset += data.count

            if total == nil {
                if http.statusCode == 200 {
                    total = offset // 서버가 Range를 무시하고 전체를 보냄
                } else if let range = http.value(forHTTPHeaderField: "Content-Range"),
                          let slash = range.lastIndex(of: "/"),
                          let size = Int(range[range.index(after: slash)...]) {
                    total = size
                }
            }
            if let total, total > 0 {
                progress(min(Double(offset) / Double(total), 1))
            }
            if data.isEmpty || data.count < chunkSize || (total.map { offset >= $0 } ?? false) {
                break
            }
        }
        progress(1)
    }
}
