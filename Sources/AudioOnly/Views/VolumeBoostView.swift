import AppKit
import SwiftUI

/// 음량을 올릴 파일 목록. 이 값이 생기면 음량 올리기 창이 뜬다.
struct VolumeBoostRequest: Identifiable {
    let id = UUID()
    let files: [URL]
}

enum VolumeBoostPicker {
    /// 음량을 올릴 오디오 파일(또는 폴더)을 고르는 패널을 띄운다.
    @MainActor
    static func chooseFiles(in directory: URL) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = directory
        panel.prompt = "선택"
        panel.message = "음량을 올릴 오디오 파일 또는 폴더를 선택하세요. (MP3 · M4A · Opus · OGG · FLAC · WAV · AIFF)"
        guard panel.runModal() == .OK else { return [] }
        let files = VolumeBoostCommand.collectAudioFiles(from: panel.urls)
        if files.isEmpty { NSSound.beep() }
        return files
    }
}

/// 몇 % 올릴지 고른 뒤 작업 목록에 넣는다. 결과는 원래 파일에 같은 형식으로 저장된다.
struct VolumeBoostSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager
    @EnvironmentObject private var queue: JobQueue
    @Environment(\.dismiss) private var dismiss
    let files: [URL]

    @AppStorage("volumeBoostPercent") private var percent = 50.0

    private static let presets: [Double] = [10, 25, 50, 100, 200]

    private var infoText: String {
        let gain = 1 + percent / 100
        let decibels = 20 * log10(gain)
        return String(format: "원래 소리의 %g배 (+%.1f dB)로 키워 원래 파일에 같은 형식으로 저장합니다. ", gain, decibels)
            + "제목 · 앨범 아트 · 파일 날짜는 그대로 둡니다. 너무 크게 올리면 큰 소리 부분이 잘려 찌그러질 수 있습니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("음량 올리기").font(.title2.weight(.semibold))

            Group {
                if files.count == 1 {
                    Text(files[0].lastPathComponent)
                } else {
                    Text("\(files.count)개 파일: ")
                        + Text(files.map(\.lastPathComponent).joined(separator: ", ")).foregroundColor(.secondary)
                }
            }
            .lineLimit(3)
            .truncationMode(.tail)

            HStack {
                Slider(value: $percent, in: 10...300, step: 5) {
                    Text("올릴 음량")
                }
                Text("+\(Int(percent))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }

            HStack {
                ForEach(Self.presets, id: \.self) { value in
                    Button("+\(Int(value))%") { percent = value }
                }
            }

            Text(infoText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if tools.ffmpegURL == nil {
                Text("ffmpeg가 없습니다. 터미널에서 `brew install ffmpeg` 를 실행하세요.")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("음량 올리기") {
                    enqueue()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty || tools.ffmpegURL == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func enqueue() {
        let options = settings.makeOptions(tools: tools)
        let percent = Int(percent)
        let jobs = files.map { file in
            Job(
                source: .volumeBoost(
                    input: file,
                    percent: percent,
                    temp: VolumeBoostCommand.temporaryOutputURL(for: file)
                ),
                options: options,
                title: "음량 +\(percent)%: \(file.lastPathComponent)"
            )
        }
        queue.enqueue(jobs)
    }
}
