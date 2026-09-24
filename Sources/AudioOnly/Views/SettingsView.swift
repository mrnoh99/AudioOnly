import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            toolsTab
                .tabItem { Label("도구", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Toggle("메타데이터(제목, 아티스트 등) 포함", isOn: $settings.embedMetadata)
            Toggle("썸네일을 앨범 아트로 넣기 (MP3, M4A, FLAC)", isOn: $settings.embedThumbnail)
            Stepper("동시 작업 수: \(settings.maxConcurrent)", value: $settings.maxConcurrent, in: 1...6)
            Picker("브라우저 쿠키 사용", selection: $settings.cookieBrowser) {
                ForEach(CookieBrowser.allCases) { browser in
                    Text(browser.displayName).tag(browser)
                }
            }
            Text("연령 제한·회원 전용 영상은 해당 브라우저에 로그인된 쿠키가 필요할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var toolsTab: some View {
        Form {
            Section("yt-dlp") {
                LabeledContent("위치", value: tools.ytDlpURL?.path ?? "찾을 수 없음")
                LabeledContent("버전", value: tools.ytDlpVersion ?? "-")
                pathField("직접 지정", text: $settings.customYtDlpPath)
                HStack {
                    Button(tools.ytDlpURL == nil ? "yt-dlp 설치" : "yt-dlp 최신 버전으로 업데이트") {
                        Task { await tools.installYtDlp(settings: settings) }
                    }
                    .disabled(tools.isInstalling)
                    if tools.isInstalling { ProgressView().controlSize(.small) }
                }
                if let message = tools.installMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Text("YouTube가 바뀌면 오래된 yt-dlp는 동작하지 않습니다. 오류가 나면 먼저 업데이트하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("ffmpeg") {
                LabeledContent("위치", value: tools.ffmpegURL?.path ?? "찾을 수 없음")
                LabeledContent("버전", value: tools.ffmpegVersion ?? "-")
                pathField("직접 지정", text: $settings.customFfmpegPath)
                Text("설치: 터미널에서 `brew install ffmpeg`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if tools.isChecking { ProgressView().controlSize(.small) }
                Button("다시 확인") {
                    Task { await tools.refresh(settings: settings) }
                }
            }
        }
    }

    private func pathField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text("자동 감지"))
            Button("선택…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
                if panel.runModal() == .OK, let url = panel.url {
                    text.wrappedValue = url.path
                }
            }
        }
    }
}
