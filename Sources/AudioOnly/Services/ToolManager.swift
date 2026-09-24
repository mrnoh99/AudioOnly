import Foundation

enum ToolLocator {
    /// GUI 앱은 셸의 PATH를 물려받지 않으므로 Homebrew 등 일반적인 설치 위치를 직접 찾는다.
    static let searchDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/local/bin",
        "/usr/bin",
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
    ]

    /// 앱이 직접 내려받은 yt-dlp가 저장되는 위치
    static var managedBinDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("AudioOnly/bin", isDirectory: true)
    }

    static func find(_ name: String, customPath: String, extraDirectories: [String] = []) -> URL? {
        let fm = FileManager.default
        let custom = (customPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if !custom.isEmpty, fm.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        var directories = extraDirectories + searchDirectories
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init)
        }
        for directory in directories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchDirectories + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        // 파이프로 출력할 때 파이썬이 버퍼링하면 진행률이 늦게 도착한다.
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    static func firstOutputLine(of executable: URL, arguments: [String]) async -> String? {
        let collector = LineCollector()
        let process = RunningProcess()
        guard
            let status = try? await process.run(
                executable: executable,
                arguments: arguments,
                environment: processEnvironment,
                onLine: { line, stream in collector.append(line, stream) }
            ),
            status == 0
        else { return nil }
        return collector.stdout.first?.trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
final class ToolManager: ObservableObject {
    @Published private(set) var ytDlpURL: URL?
    @Published private(set) var ffmpegURL: URL?
    @Published private(set) var ytDlpVersion: String?
    @Published private(set) var ffmpegVersion: String?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published var installMessage: String?

    static let ytDlpDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    var isReady: Bool { ytDlpURL != nil && ffmpegURL != nil }

    func refresh(settings: AppSettings) async {
        isChecking = true
        defer { isChecking = false }

        ytDlpURL = ToolLocator.find(
            "yt-dlp",
            customPath: settings.customYtDlpPath,
            extraDirectories: [ToolLocator.managedBinDirectory.path]
        )
        ffmpegURL = ToolLocator.find("ffmpeg", customPath: settings.customFfmpegPath)

        if let ytDlpURL {
            ytDlpVersion = await ToolLocator.firstOutputLine(of: ytDlpURL, arguments: ["--version"])
        } else {
            ytDlpVersion = nil
        }
        if let ffmpegURL, let line = await ToolLocator.firstOutputLine(of: ffmpegURL, arguments: ["-version"]) {
            // "ffmpeg version 7.1 Copyright ..." -> "7.1"
            let parts = line.split(separator: " ")
            ffmpegVersion = parts.count >= 3 ? String(parts[2]) : line
        } else {
            ffmpegVersion = nil
        }
    }

    /// GitHub 릴리스에서 yt-dlp 단일 실행 파일(macOS용)을 내려받아 설치/업데이트한다.
    func installYtDlp(settings: AppSettings) async {
        isInstalling = true
        installMessage = "yt-dlp 다운로드 중…"
        defer { isInstalling = false }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: Self.ytDlpDownloadURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(
                    domain: "AudioOnly",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
                )
            }
            let fm = FileManager.default
            let directory = ToolLocator.managedBinDirectory
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("yt-dlp")
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: temporaryURL, to: destination)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            await refresh(settings: settings)
            installMessage = "yt-dlp \(ytDlpVersion ?? "") 설치 완료"
        } catch {
            installMessage = "yt-dlp 설치 실패: \(error.localizedDescription)"
        }
    }
}
