import Foundation

enum AudioFormat: String, CaseIterable, Identifiable {
    case mp3, m4a, opus, flac, wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A (AAC)"
        case .opus: return "Opus"
        case .flac: return "FLAC (무손실)"
        case .wav: return "WAV (무손실)"
        }
    }

    var fileExtension: String { rawValue }

    var isLossless: Bool { self == .flac || self == .wav }

    /// yt-dlp가 썸네일을 앨범 아트로 넣을 수 있는 형식
    var supportsThumbnail: Bool { self == .mp3 || self == .m4a || self == .flac }

    func ffmpegCodecArguments(bitrate: Int) -> [String] {
        switch self {
        case .mp3: return ["-c:a", "libmp3lame", "-b:a", "\(bitrate)k"]
        case .m4a: return ["-c:a", "aac", "-b:a", "\(bitrate)k"]
        case .opus: return ["-c:a", "libopus", "-b:a", "\(min(bitrate, 256))k"]
        case .flac: return ["-c:a", "flac"]
        case .wav: return ["-c:a", "pcm_s16le"]
        }
    }
}

enum CookieBrowser: String, CaseIterable, Identifiable {
    case none, safari, chrome, firefox, edge, brave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "사용 안 함"
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        case .brave: return "Brave"
        }
    }
}

/// 작업을 큐에 넣는 시점의 설정 스냅샷. 이후 설정을 바꿔도 이미 추가된 작업에는 영향이 없다.
struct ExtractOptions {
    var format: AudioFormat
    var bitrate: Int
    var embedMetadata: Bool
    var embedThumbnail: Bool
    var cookieBrowser: CookieBrowser
    var ytDlpURL: URL?
    var ffmpegURL: URL?
}

@MainActor
final class AppSettings: ObservableObject {
    static let bitrates = [128, 160, 192, 256, 320]

    private enum Keys {
        static let outputDirectory = "outputDirectory"
        static let format = "format"
        static let bitrate = "bitrate"
        static let embedMetadata = "embedMetadata"
        static let embedThumbnail = "embedThumbnail"
        static let saveNextToSource = "saveNextToSource"
        static let maxConcurrent = "maxConcurrent"
        static let cookieBrowser = "cookieBrowser"
        static let customYtDlpPath = "customYtDlpPath"
        static let customFfmpegPath = "customFfmpegPath"
    }

    private let defaults = UserDefaults.standard

    @Published var outputDirectory: URL {
        didSet { defaults.set(outputDirectory.path, forKey: Keys.outputDirectory) }
    }
    @Published var format: AudioFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.format) }
    }
    @Published var bitrate: Int {
        didSet { defaults.set(bitrate, forKey: Keys.bitrate) }
    }
    @Published var embedMetadata: Bool {
        didSet { defaults.set(embedMetadata, forKey: Keys.embedMetadata) }
    }
    @Published var embedThumbnail: Bool {
        didSet { defaults.set(embedThumbnail, forKey: Keys.embedThumbnail) }
    }
    /// 로컬 파일 추출 시 결과를 원본 파일과 같은 폴더에 저장
    @Published var saveNextToSource: Bool {
        didSet { defaults.set(saveNextToSource, forKey: Keys.saveNextToSource) }
    }
    @Published var maxConcurrent: Int {
        didSet { defaults.set(maxConcurrent, forKey: Keys.maxConcurrent) }
    }
    @Published var cookieBrowser: CookieBrowser {
        didSet { defaults.set(cookieBrowser.rawValue, forKey: Keys.cookieBrowser) }
    }
    @Published var customYtDlpPath: String {
        didSet { defaults.set(customYtDlpPath, forKey: Keys.customYtDlpPath) }
    }
    @Published var customFfmpegPath: String {
        didSet { defaults.set(customFfmpegPath, forKey: Keys.customFfmpegPath) }
    }

    static var defaultOutputDirectory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
        return music.appendingPathComponent("AudioOnly", isDirectory: true)
    }

    init() {
        let d = UserDefaults.standard
        if let path = d.string(forKey: Keys.outputDirectory), !path.isEmpty {
            outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputDirectory = Self.defaultOutputDirectory
        }
        format = AudioFormat(rawValue: d.string(forKey: Keys.format) ?? "") ?? .mp3
        let storedBitrate = d.integer(forKey: Keys.bitrate)
        bitrate = Self.bitrates.contains(storedBitrate) ? storedBitrate : 192
        embedMetadata = d.object(forKey: Keys.embedMetadata) as? Bool ?? true
        embedThumbnail = d.object(forKey: Keys.embedThumbnail) as? Bool ?? true
        saveNextToSource = d.object(forKey: Keys.saveNextToSource) as? Bool ?? false
        let storedConcurrent = d.integer(forKey: Keys.maxConcurrent)
        maxConcurrent = (1...6).contains(storedConcurrent) ? storedConcurrent : 2
        cookieBrowser = CookieBrowser(rawValue: d.string(forKey: Keys.cookieBrowser) ?? "") ?? .none
        customYtDlpPath = d.string(forKey: Keys.customYtDlpPath) ?? ""
        customFfmpegPath = d.string(forKey: Keys.customFfmpegPath) ?? ""
    }

    func makeOptions(tools: ToolManager) -> ExtractOptions {
        ExtractOptions(
            format: format,
            bitrate: bitrate,
            embedMetadata: embedMetadata,
            embedThumbnail: embedThumbnail,
            cookieBrowser: cookieBrowser,
            ytDlpURL: tools.ytDlpURL,
            ffmpegURL: tools.ffmpegURL
        )
    }
}
