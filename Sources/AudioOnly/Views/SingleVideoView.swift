import AppKit
import SwiftUI

/// YouTube 개별 영상 주소 (여러 줄 입력 가능)
struct SingleVideoView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager
    @EnvironmentObject private var queue: JobQueue
    @State private var text = ""
    @State private var message: String?

    private var urls: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YouTube 영상 주소를 한 줄에 하나씩 붙여넣으세요.")
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if text.isEmpty {
                    Text("https://www.youtube.com/watch?v=…\nhttps://youtu.be/…")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(11)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        text = text.isEmpty ? clip : text + "\n" + clip
                    }
                } label: {
                    Label("클립보드 붙여넣기", systemImage: "doc.on.clipboard")
                }
                Button("지우기") { text = "" }
                    .disabled(text.isEmpty)

                if let message {
                    Text(message).foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button {
                    enqueue()
                } label: {
                    Label("오디오 추출 (\(urls.count))", systemImage: "waveform")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(urls.isEmpty || tools.ytDlpURL == nil)
            }
        }
        .padding(8)
    }

    private func enqueue() {
        let options = settings.makeOptions(tools: tools)
        let directory = settings.outputDirectory
        let template = YTDLPCommand.escapeTemplateLiteral(directory.path) + "/%(title)s.%(ext)s"
        // 영상 없이 재생목록만 가리키는 주소는 여기서 받지 않는다.
        let playlistOnly = urls.filter { $0.contains("list=") && !$0.contains("v=") }
        let jobs = urls.filter { !playlistOnly.contains($0) }.map { url in
            Job(
                source: .youtube(url: url, outputTemplate: template, outputDirectory: directory),
                options: options,
                title: url
            )
        }
        queue.enqueue(jobs)
        if playlistOnly.isEmpty {
            message = "\(jobs.count)개 작업을 추가했습니다."
            text = ""
        } else {
            message = "재생목록 주소 \(playlistOnly.count)개는 ‘재생목록’ 탭에서 추가하세요."
            text = playlistOnly.joined(separator: "\n")
        }
    }
}
