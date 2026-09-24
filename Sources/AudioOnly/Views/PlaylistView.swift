import AppKit
import SwiftUI

/// YouTube 재생목록 주소 → 항목 조회 → 선택한 영상의 오디오 추출
struct PlaylistView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tools: ToolManager
    @EnvironmentObject private var queue: JobQueue

    @State private var url = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playlistTitle = ""
    @State private var entries: [PlaylistEntry] = []
    @State private var selection: Set<String> = []
    @State private var useSubfolder = true
    @State private var numbered = true
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("https://www.youtube.com/playlist?list=…", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(load)
                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        url = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("클립보드 붙여넣기")
                if isLoading {
                    ProgressView().controlSize(.small)
                    Button("중지") { loadTask?.cancel() }
                } else {
                    Button("목록 불러오기", action: load)
                        .disabled(trimmedURL.isEmpty || tools.ytDlpURL == nil)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(isLoading ? "재생목록을 불러오는 중…" : "재생목록 주소를 입력하고 ‘목록 불러오기’를 누르세요.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text(playlistTitle).font(.headline).lineLimit(1)
                    Text("\(selection.count) / \(entries.count)개 선택").foregroundStyle(.secondary)
                    Spacer()
                    Button("모두 선택") { selection = Set(entries.map(\.id)) }
                    Button("선택 해제") { selection.removeAll() }
                }

                List(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Toggle(isOn: binding(for: entry.id)) {
                        HStack {
                            Text(String(format: "%3d", index + 1))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.displayTitle).lineLimit(1)
                            Spacer()
                            if let duration = entry.durationText {
                                Text(duration)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))

                HStack {
                    Toggle("재생목록 이름으로 하위 폴더 만들기", isOn: $useSubfolder)
                    Toggle("파일 이름 앞에 번호 붙이기", isOn: $numbered)
                    Spacer()
                    Button {
                        enqueue()
                    } label: {
                        Label("선택 항목 오디오 추출 (\(selection.count))", systemImage: "waveform")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty || tools.ytDlpURL == nil)
                }
            }
        }
        .padding(8)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(id) },
            set: { isOn in
                if isOn { selection.insert(id) } else { selection.remove(id) }
            }
        )
    }

    private func load() {
        let target = trimmedURL
        guard !target.isEmpty, !isLoading else { return }
        let options = settings.makeOptions(tools: tools)
        isLoading = true
        errorMessage = nil
        entries = []
        selection = []
        loadTask = Task { @MainActor in
            do {
                let info = try await PlaylistService.fetch(url: target, options: options)
                playlistTitle = info.title
                entries = info.entries
                selection = Set(info.entries.map(\.id))
            } catch {
                errorMessage = Task.isCancelled ? "취소했습니다." : error.localizedDescription
            }
            isLoading = false
        }
    }

    private func enqueue() {
        let options = settings.makeOptions(tools: tools)
        var directory = settings.outputDirectory
        if useSubfolder {
            directory.appendPathComponent(FileNaming.sanitize(playlistTitle), isDirectory: true)
        }
        let jobs = entries.enumerated().compactMap { index, entry -> Job? in
            guard selection.contains(entry.id) else { return nil }
            let prefix = numbered ? String(format: "%03d - ", index + 1) : ""
            let template = YTDLPCommand.escapeTemplateLiteral(directory.path) + "/\(prefix)%(title)s.%(ext)s"
            return Job(
                source: .youtube(url: entry.watchURL, outputTemplate: template, outputDirectory: directory),
                options: options,
                title: entry.displayTitle,
                group: playlistTitle
            )
        }
        queue.enqueue(jobs)
        selection.removeAll()
    }
}
