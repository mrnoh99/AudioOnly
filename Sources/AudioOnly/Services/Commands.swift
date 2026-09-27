import Foundation

enum YTDLPCommand {
    static let progressPrefix = "AOPROG "
    static let titlePrefix = "AOTITLE "
    static let filePrefix = "AOFILE "

    /// 영상 1개를 받아 오디오만 추출하는 인자 목록
    static func downloadArguments(url: String, outputTemplate: String, options: ExtractOptions) -> [String] {
        var args = [
            "--newline",
            "--no-colors",
            "--no-playlist",
            "--progress",
            "--progress-template", "download:\(progressPrefix)%(progress._percent_str)s",
            "--print", "before_dl:\(titlePrefix)%(title)s",
            "--print", "after_move:\(filePrefix)%(filepath)s",
            "-f", "bestaudio/best",
            "-x",
            "--audio-format", options.format.rawValue,
            "-o", outputTemplate,
        ]
        if !options.format.isLossless {
            args += ["--audio-quality", "\(options.bitrate)K"]
        }
        if let ffmpeg = options.ffmpegURL {
            args += ["--ffmpeg-location", ffmpeg.path]
        }
        if options.embedMetadata {
            args.append("--embed-metadata")
        }
        if options.embedThumbnail && options.format.supportsThumbnail {
            args += ["--embed-thumbnail", "--convert-thumbnails", "jpg"]
        }
        args += cookieArguments(options)
        args += ["--", url]
        return args
    }

    /// 재생목록 항목만 빠르게 조회하는 인자 목록 (다운로드하지 않음)
    static func playlistArguments(url: String, options: ExtractOptions) -> [String] {
        ["--flat-playlist", "--yes-playlist", "-J", "--no-warnings", "--no-colors"]
            + cookieArguments(options)
            + ["--", url]
    }

    private static func cookieArguments(_ options: ExtractOptions) -> [String] {
        options.cookieBrowser == .none ? [] : ["--cookies-from-browser", options.cookieBrowser.rawValue]
    }

    /// yt-dlp 출력 템플릿 안에 그대로 들어갈 문자열을 안전하게 만든다.
    static func escapeTemplateLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%%")
    }
}

enum FFmpegCommand {
    static func extractArguments(input: URL, output: URL, options: ExtractOptions) -> [String] {
        var args = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i", input.path,
            "-map", "0:a:0",
            "-vn", "-sn", "-dn",
        ]
        args += options.format.ffmpegCodecArguments(bitrate: options.bitrate)
        args += ["-map_metadata", options.embedMetadata ? "0" : "-1"]
        args += ["-progress", "pipe:1", "-nostats", output.path]
        return args
    }
}

enum FileNaming {
    private static let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")

    /// 파일/폴더 이름으로 쓸 수 있도록 정리
    static func sanitize(_ name: String) -> String {
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.hasPrefix(".") ? "_" + String(cleaned.dropFirst()) : cleaned
        return trimmed.isEmpty ? "untitled" : String(trimmed.prefix(180))
    }

    /// 이미 존재하는 파일(또는 이번에 예약된 경로)과 겹치지 않는 출력 경로를 만든다.
    static func uniqueOutputURL(for input: URL, in directory: URL, fileExtension: String, reserved: inout Set<String>) -> URL {
        let fm = FileManager.default
        let base = input.deletingPathExtension().lastPathComponent
        let inputPath = input.standardizedFileURL.path
        var index = 0
        while true {
            let name = index == 0 ? base : "\(base) (\(index))"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            let path = candidate.standardizedFileURL.path
            if path != inputPath && !reserved.contains(path) && !fm.fileExists(atPath: path) {
                reserved.insert(path)
                return candidate
            }
            index += 1
        }
    }

    static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mkv", "webm", "mov", "avi", "flv", "wmv", "ts", "mts", "m2ts", "3gp", "mpg", "mpeg", "ogv",
        "m4a", "mp3", "aac", "wav", "flac", "ogg", "oga", "opus", "wma", "aiff", "aif", "caf",
    ]

    /// 파일과 폴더(하위 폴더 포함)에서 미디어 파일을 모은다.
    static func collectMediaFiles(from urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in enumerator where mediaExtensions.contains(file.pathExtension.lowercased()) {
                    result.append(file)
                }
            } else if mediaExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
