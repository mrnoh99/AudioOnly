import Foundation

struct PlaylistVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let duration: Int?

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let (h, m, s) = (duration / 3600, (duration % 3600) / 60, duration % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct PlaylistResult {
    let title: String
    let videos: [PlaylistVideo]
}

enum PlaylistError: LocalizedError {
    case invalidURL
    case parseFailed
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "재생목록 주소(list=…)를 인식하지 못했습니다."
        case .parseFailed: return "재생목록 페이지를 해석하지 못했습니다. 비공개 재생목록이거나 YouTube 구조가 바뀌었을 수 있습니다."
        case .empty: return "재생목록에서 영상을 찾지 못했습니다."
        }
    }
}

/// YouTube 재생목록 페이지(ytInitialData)와 내부 browse API로 전체 항목을 가져온다.
enum PlaylistFetcher {
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let maxPages = 100

    static func playlistID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: text),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value,
           !list.isEmpty {
            return list
        }
        let isRawID = text.count >= 12 && text.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
        return isRawID ? text : nil
    }

    static func fetch(playlistID: String) async throws -> PlaylistResult {
        var components = URLComponents(string: "https://www.youtube.com/playlist")!
        components.queryItems = [URLQueryItem(name: "list", value: playlistID), URLQueryItem(name: "hl", value: "ko")]
        var request = URLRequest(url: components.url!)
        applyHeaders(to: &request)
        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data, as: UTF8.self)

        guard let initialText = extractJSONObject(after: "ytInitialData = ", in: html)
            ?? extractJSONObject(after: "ytInitialData\"] = ", in: html),
            let initial = try? JSONSerialization.jsonObject(with: Data(initialText.utf8))
        else {
            throw PlaylistError.parseFailed
        }

        let clientVersion = firstMatch(#""INNERTUBE_CLIENT_VERSION":"([^"]+)""#, in: html) ?? "2.20250101.00.00"
        let apiKey = firstMatch(#""INNERTUBE_API_KEY":"([^"]+)""#, in: html)

        var collector = Collector()
        collector.walk(initial)
        let title = playlistTitle(in: initial) ?? "Playlist"

        var pages = 0
        while let token = collector.takeContinuation(), pages < maxPages {
            try Task.checkCancellation()
            let json = try await browse(continuation: token, clientVersion: clientVersion, apiKey: apiKey)
            collector.walk(json)
            pages += 1
        }

        guard !collector.videos.isEmpty else { throw PlaylistError.empty }
        return PlaylistResult(title: title, videos: collector.videos)
    }

    // MARK: - 네트워크

    private static func applyHeaders(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ko-KR,ko;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // EU 동의 페이지로 넘어가지 않도록
        request.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
    }

    private static func browse(continuation: String, clientVersion: String, apiKey: String?) async throws -> Any {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/browse")!
        var query = [URLQueryItem(name: "prettyPrint", value: "false")]
        if let apiKey { query.append(URLQueryItem(name: "key", value: apiKey)) }
        components.queryItems = query

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        let body: [String: Any] = [
            "context": ["client": ["clientName": "WEB", "clientVersion": clientVersion, "hl": "ko"]],
            "continuation": continuation,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw YouTubeError.http(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - 해석

    /// 영상 항목과 다음 페이지 토큰을 모은다.
    private struct Collector {
        var videos: [PlaylistVideo] = []
        private var seen: Set<String> = []
        private var continuation: String?

        mutating func takeContinuation() -> String? {
            defer { continuation = nil }
            return continuation
        }

        mutating func walk(_ node: Any) {
            if let array = node as? [Any] {
                for element in array { walk(element) }
                return
            }
            guard let dict = node as? [String: Any] else { return }

            if let renderer = dict["playlistVideoRenderer"] as? [String: Any]
                ?? dict["playlistPanelVideoRenderer"] as? [String: Any],
               let id = renderer["videoId"] as? String {
                let seconds = (renderer["lengthSeconds"] as? String).flatMap(Int.init)
                add(id: id, title: PlaylistFetcher.text(renderer["title"]), duration: seconds)
                return
            }
            if let lockup = dict["lockupViewModel"] as? [String: Any],
               (lockup["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_VIDEO",
               let id = lockup["contentId"] as? String {
                let metadata = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any]
                let title = (metadata?["title"] as? [String: Any])?["content"] as? String
                add(id: id, title: title, duration: nil)
                return
            }
            if let renderer = dict["continuationItemRenderer"] as? [String: Any] {
                if let token = PlaylistFetcher.findString(forKey: "token", under: "continuationCommand", in: renderer) {
                    continuation = token
                }
                return
            }
            for value in dict.values { walk(value) }
        }

        private mutating func add(id: String, title: String?, duration: Int?) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            videos.append(PlaylistVideo(id: id, title: title ?? id, duration: duration))
        }
    }

    static func text(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// `container` 키 아래 어딘가에 있는 `key` 문자열 값을 찾는다.
    static func findString(forKey key: String, under container: String, in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let inner = dict[container] as? [String: Any], let value = inner[key] as? String {
                return value
            }
            for value in dict.values {
                if let found = findString(forKey: key, under: container, in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findString(forKey: key, under: container, in: value) { return found }
            }
        }
        return nil
    }

    private static func playlistTitle(in initial: Any) -> String? {
        if let title = findString(forKey: "title", under: "playlistMetadataRenderer", in: initial) {
            return title
        }
        return findString(forKey: "title", under: "microformatDataRenderer", in: initial)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    /// `marker` 뒤에 오는 JSON 객체를 중괄호 짝을 맞춰 잘라낸다.
    static func extractJSONObject(after marker: String, in html: String) -> String? {
        guard let markerRange = html.range(of: marker) else { return nil }
        let bytes = Array(html.utf8[markerRange.upperBound...])
        guard let start = bytes.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 {
                    return String(decoding: bytes[start...index], as: UTF8.self)
                }
            }
            index += 1
        }
        return nil
    }
}
