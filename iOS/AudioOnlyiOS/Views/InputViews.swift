import SwiftUI
import UIKit

/// YouTube 개별 영상 주소 (여러 줄 가능)
struct URLInputView: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    private var videoIDs: [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .compactMap { YouTubeLinks.videoID(from: String($0)) }
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(.system(.callout, design: .monospaced))
                            .frame(minHeight: 160)
                            .focused($focused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if text.isEmpty {
                            Text("https://youtu.be/…\nhttps://www.youtube.com/watch?v=…")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
                    HStack {
                        Button {
                            if let clip = UIPasteboard.general.string {
                                text = text.isEmpty ? clip : text + "\n" + clip
                            }
                        } label: {
                            Label("붙여넣기", systemImage: "doc.on.clipboard")
                        }
                        Spacer()
                        Button("지우기", role: .destructive) { text = "" }
                            .disabled(text.isEmpty)
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("YouTube 영상 주소 (한 줄에 하나)")
                } footer: {
                    Text("YouTube 앱에서 공유 → 링크 복사 후 붙여넣거나, Safari에서 링크를 이 화면으로 끌어다 놓으세요. 인식된 영상: \(videoIDs.count)개")
                }

                Section {
                    Button {
                        enqueue()
                    } label: {
                        Label("오디오 추출 (\(model.format.displayName))", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(videoIDs.isEmpty)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let links = urls.filter { !$0.isFileURL }.map(\.absoluteString)
                guard !links.isEmpty else { return false }
                text = ([text].filter { !$0.isEmpty } + links).joined(separator: "\n")
                return true
            }
            .navigationTitle("YouTube 주소")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { focused = false }
                }
            }
        }
    }

    private func enqueue() {
        let ids = videoIDs
        model.enqueueVideos(ids.map { (id: $0, title: $0, number: nil) })
        message = "\(ids.count)개 작업을 추가했습니다. 진행 상황은 ‘보관함’ 탭에서 볼 수 있습니다."
        text = ""
        focused = false
    }
}

/// YouTube 재생목록
struct PlaylistInputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var url = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var result: PlaylistResult?
    @State private var selection: Set<String> = []
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("https://www.youtube.com/playlist?list=…", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(load)
                    HStack {
                        Button {
                            if let clip = UIPasteboard.general.string {
                                url = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Label("붙여넣기", systemImage: "doc.on.clipboard")
                        }
                        Spacer()
                        if isLoading {
                            ProgressView()
                            Button("중지") { loadTask?.cancel() }
                        } else {
                            Button("목록 불러오기", action: load)
                                .disabled(PlaylistFetcher.playlistID(from: url) == nil)
                        }
                    }
                    .buttonStyle(.borderless)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                if let result {
                    Section {
                        ForEach(Array(result.videos.enumerated()), id: \.element.id) { index, video in
                            Button {
                                if selection.contains(video.id) {
                                    selection.remove(video.id)
                                } else {
                                    selection.insert(video.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selection.contains(video.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selection.contains(video.id) ? Color.accentColor : .secondary)
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 24, alignment: .trailing)
                                    if sizeClass == .regular {
                                        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg")) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.secondary.opacity(0.15)
                                        }
                                        .frame(width: 96, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text(video.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    if let duration = video.durationText {
                                        Text(duration)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(result.title) · \(selection.count)/\(result.videos.count)")
                                .lineLimit(1)
                            Spacer()
                            Button(selection.count == result.videos.count ? "선택 해제" : "모두 선택") {
                                if selection.count == result.videos.count {
                                    selection.removeAll()
                                } else {
                                    selection = Set(result.videos.map(\.id))
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("재생목록")
            .safeAreaInset(edge: .bottom) {
                if result != nil {
                    Button {
                        enqueue()
                    } label: {
                        Label("선택한 \(selection.count)개 오디오 추출", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(selection.isEmpty)
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private func load() {
        guard let id = PlaylistFetcher.playlistID(from: url), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        result = nil
        selection = []
        loadTask = Task { @MainActor in
            do {
                let fetched = try await PlaylistFetcher.fetch(playlistID: id)
                result = fetched
                selection = Set(fetched.videos.map(\.id))
            } catch {
                errorMessage = Task.isCancelled ? "취소했습니다." : error.localizedDescription
            }
            isLoading = false
        }
    }

    private func enqueue() {
        guard let result else { return }
        let videos = result.videos.enumerated()
            .filter { selection.contains($0.element.id) }
            .map { (id: $0.element.id, title: $0.element.title, number: Optional($0.offset + 1)) }
        model.enqueueVideos(videos, playlistTitle: result.title)
        selection.removeAll()
        if sizeClass == .compact { model.selectedTab = .library }
    }
}
