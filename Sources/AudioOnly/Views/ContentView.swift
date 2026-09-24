import AppKit
import SwiftUI

enum SourceTab: Hashable {
    case single, playlist, local
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager
    @EnvironmentObject private var queue: JobQueue
    @State private var tab: SourceTab = .single

    var body: some View {
        VStack(spacing: 0) {
            ToolStatusBanner()
            VSplitView {
                VStack(spacing: 0) {
                    TabView(selection: $tab) {
                        SingleVideoView()
                            .tabItem { Label("YouTube 주소", systemImage: "play.rectangle") }
                            .tag(SourceTab.single)
                        PlaylistView()
                            .tabItem { Label("재생목록", systemImage: "list.bullet.rectangle") }
                            .tag(SourceTab.playlist)
                        LocalFilesView()
                            .tabItem { Label("다운로드한 파일", systemImage: "folder") }
                            .tag(SourceTab.local)
                    }
                    .padding([.horizontal, .top], 12)
                    OutputOptionsBar()
                        .padding(12)
                }
                .frame(minHeight: 330, idealHeight: 380)

                JobListView()
                    .frame(minHeight: 180)
            }
        }
        .onAppear { queue.maxConcurrent = settings.maxConcurrent }
        .onReceive(settings.$maxConcurrent) { queue.maxConcurrent = $0 }
    }
}

/// yt-dlp / ffmpeg 가 없을 때 안내
struct ToolStatusBanner: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager

    var body: some View {
        if !tools.isReady && !tools.isChecking {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    if tools.ytDlpURL == nil {
                        Text("yt-dlp가 없습니다. 아래 버튼으로 설치하거나 터미널에서 `brew install yt-dlp` 를 실행하세요.")
                    }
                    if tools.ffmpegURL == nil {
                        Text("ffmpeg가 없습니다. 터미널에서 `brew install ffmpeg` 를 실행한 뒤 ‘다시 확인’을 누르세요.")
                    }
                    if let message = tools.installMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                Spacer()
                if tools.ytDlpURL == nil {
                    Button("yt-dlp 설치") {
                        Task { await tools.installYtDlp(settings: settings) }
                    }
                    .disabled(tools.isInstalling)
                }
                Button("다시 확인") {
                    Task { await tools.refresh(settings: settings) }
                }
            }
            .padding(12)
            .background(Color.yellow.opacity(0.12))
        }
    }
}

/// 출력 형식 / 음질 / 저장 폴더
struct OutputOptionsBar: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 16) {
            Picker("형식", selection: $settings.format) {
                ForEach(AudioFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .frame(width: 190)

            Picker("음질", selection: $settings.bitrate) {
                ForEach(AppSettings.bitrates, id: \.self) { rate in
                    Text("\(rate) kbps").tag(rate)
                }
            }
            .frame(width: 150)
            .disabled(settings.format.isLossless)

            Divider().frame(height: 20)

            Label {
                Text(settings.outputDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(settings.outputDirectory.path)
            } icon: {
                Image(systemName: "folder")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("변경…", action: chooseFolder)
            Button {
                let dir = settings.outputDirectory
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                NSWorkspace.shared.open(dir)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .help("Finder에서 열기")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.outputDirectory
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
    }
}
