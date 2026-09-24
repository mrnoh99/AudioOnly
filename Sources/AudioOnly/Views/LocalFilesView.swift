import AppKit
import SwiftUI

/// 이미 내려받은 영상/오디오 파일 목록에서 오디오만 추출
struct LocalFilesView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager
    @EnvironmentObject private var queue: JobQueue

    @State private var files: [URL] = []
    @State private var selection: Set<URL> = []
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    addFromPanel()
                } label: {
                    Label("파일/폴더 추가…", systemImage: "plus")
                }
                Button {
                    add(FileNaming.collectMediaFiles(from: [downloadsDirectory]))
                } label: {
                    Label("다운로드 폴더 전체", systemImage: "arrow.down.circle")
                }
                .help(downloadsDirectory.path)
                Button("선택 삭제") {
                    files.removeAll { selection.contains($0) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("모두 지우기") {
                    files.removeAll()
                    selection.removeAll()
                }
                .disabled(files.isEmpty)
                Spacer()
                Text("\(files.count)개 파일").foregroundStyle(.secondary)
            }

            ZStack {
                List(files, id: \.self, selection: $selection) { file in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(file.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(file.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .contextMenu {
                        Button("Finder에서 보기") {
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                        }
                        Button("목록에서 제거") {
                            files.removeAll { $0 == file }
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))

                if files.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("다운로드한 영상 파일이나 폴더를 여기로 끌어다 놓으세요.")
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .opacity(isDropTargeted ? 1 : 0)
            )
            .dropDestination(for: URL.self) { urls, _ in
                add(FileNaming.collectMediaFiles(from: urls.filter(\.isFileURL)))
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack {
                Toggle("원본 파일과 같은 폴더에 저장", isOn: $settings.saveNextToSource)
                Spacer()
                Button {
                    enqueue()
                } label: {
                    Label(extractLabel, systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .disabled(files.isEmpty || tools.ffmpegURL == nil)
            }
        }
        .padding(8)
    }

    private var extractLabel: String {
        selection.isEmpty ? "모두 오디오 추출 (\(files.count))" : "선택 항목 오디오 추출 (\(selection.count))"
    }

    private var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    private func add(_ urls: [URL]) {
        let existing = Set(files)
        files.append(contentsOf: urls.filter { !existing.contains($0) })
    }

    private func addFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = downloadsDirectory
        panel.prompt = "추가"
        panel.message = "오디오를 추출할 영상 파일 또는 폴더를 선택하세요."
        if panel.runModal() == .OK {
            add(FileNaming.collectMediaFiles(from: panel.urls))
        }
    }

    private func enqueue() {
        let targets = selection.isEmpty ? files : files.filter { selection.contains($0) }
        let options = settings.makeOptions(tools: tools)
        var reserved = Set<String>()
        let jobs = targets.map { input -> Job in
            let directory = settings.saveNextToSource ? input.deletingLastPathComponent() : settings.outputDirectory
            let output = FileNaming.uniqueOutputURL(
                for: input,
                in: directory,
                fileExtension: options.format.fileExtension,
                reserved: &reserved
            )
            return Job(
                source: .localFile(input: input, output: output),
                options: options,
                title: input.lastPathComponent
            )
        }
        queue.enqueue(jobs)
        files.removeAll { targets.contains($0) }
        selection.removeAll()
    }
}
