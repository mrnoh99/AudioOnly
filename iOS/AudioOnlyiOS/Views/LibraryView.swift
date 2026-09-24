import SwiftUI

/// 진행 중인 작업과 추출된 오디오 파일 목록 (음악 앱의 보관함처럼)
struct LibraryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case songs = "노래"
        case folders = "폴더"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: AudioPlayer
    @State private var query = ""
    @State private var mode: Mode = .songs

    private var filteredLibrary: [LibraryItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return model.library }
        return model.library.filter {
            $0.name.localizedCaseInsensitiveContains(text) || ($0.folder ?? "").localizedCaseInsensitiveContains(text)
        }
    }

    struct FolderGroup: Identifiable {
        let name: String
        let items: [LibraryItem]
        var id: String { name }
    }

    /// 폴더(재생목록)별 묶음. 저장 폴더 바로 아래 파일은 '기타'.
    private var folders: [FolderGroup] {
        let groups = Dictionary(grouping: filteredLibrary) { $0.folder ?? "" }
        return groups
            .map { key, value in
                FolderGroup(name: key, items: value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
            .sorted { lhs, rhs in
                if lhs.name.isEmpty != rhs.name.isEmpty { return !lhs.name.isEmpty }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.jobs.isEmpty {
                    Section {
                        ForEach(model.jobs) { job in
                            JobRowView(job: job)
                        }
                    } header: {
                        HStack {
                            Text("작업")
                            Spacer()
                            Button("완료 항목 지우기") { model.clearFinished() }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    Picker("보기", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if model.library.isEmpty {
                    Section {
                        Text("아직 추출한 오디오가 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                } else if mode == .songs {
                    Section {
                        PlayShuffleButtons(items: filteredLibrary)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    }
                    Section("노래 \(filteredLibrary.count)곡") {
                        ForEach(filteredLibrary) { item in
                            LibraryRowView(item: item, playlist: filteredLibrary, onDelete: delete)
                                // iPad: 다른 앱(파일, 메일, GarageBand …)으로 끌어다 놓기
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        }
                        .onDelete { offsets in
                            let visible = filteredLibrary
                            delete(offsets.map { visible[$0] })
                        }
                    }
                } else {
                    Section("폴더 \(folders.count)개") {
                        ForEach(folders) { folder in
                            NavigationLink {
                                FolderDetailView(
                                    title: folder.name.isEmpty ? "기타" : folder.name,
                                    folder: folder.name
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    FileArtworkView(url: folder.items[0].url, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name.isEmpty ? "기타" : folder.name).lineLimit(2)
                                        Text("\(folder.items.count)곡")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "저장된 오디오 검색")
            .navigationTitle("보관함")
            .refreshable { model.refreshLibrary() }
            .onAppear { model.refreshLibrary() }
        }
    }

    private func delete(_ items: [LibraryItem]) {
        player.removeFromQueue(items)
        TrackInfoCache.shared.invalidate(items.map(\.url))
        model.delete(items)
    }
}

/// 한 폴더(재생목록)의 곡 목록
struct FolderDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: AudioPlayer
    let title: String
    let folder: String

    private var items: [LibraryItem] {
        model.library
            .filter { ($0.folder ?? "") == folder }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let first = items.first {
                        FileArtworkView(url: first.url, size: 180)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    }
                    Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text("\(items.count)곡").foregroundStyle(.secondary)
                    PlayShuffleButtons(items: items)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(items) { item in
                    LibraryRowView(item: item, playlist: items, onDelete: delete)
                }
                .onDelete { offsets in
                    let visible = items
                    delete(offsets.map { visible[$0] })
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(_ items: [LibraryItem]) {
        player.removeFromQueue(items)
        TrackInfoCache.shared.invalidate(items.map(\.url))
        model.delete(items)
    }
}

/// 음악 앱의 [▶︎ 재생] [셔플] 버튼
struct PlayShuffleButtons: View {
    @EnvironmentObject private var player: AudioPlayer
    let items: [LibraryItem]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(items)
            } label: {
                Label("재생", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            Button {
                player.play(items, shuffle: true)
            } label: {
                Label("셔플", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .font(.headline)
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .disabled(items.isEmpty)
    }
}

struct LibraryRowView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: LibraryItem
    /// 이 곡을 눌렀을 때 대기열이 될 목록
    let playlist: [LibraryItem]
    var onDelete: ([LibraryItem]) -> Void = { _ in }

    private var isCurrent: Bool { player.current == item }

    var body: some View {
        Button {
            player.select(item, in: playlist)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    FileArtworkView(url: item.url, size: 48)
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35))
                            .frame(width: 48, height: 48)
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(2)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    HStack(spacing: 6) {
                        if let folder = item.folder {
                            Text(folder).lineLimit(1)
                        }
                        Text(item.url.pathExtension.uppercased())
                        Text(item.sizeText)
                        if sizeClass == .regular {
                            Text(item.modified, style: .date)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                player.playNext(item)
            } label: {
                Label("다음에 재생", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                player.playLater(item)
            } label: {
                Label("나중에 재생", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            ShareLink(item: item.url) {
                Label("공유", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                onDelete([item])
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                player.playNext(item)
            } label: {
                Label("다음에 재생", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete([item])
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

struct JobRowView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).lineLimit(2)
                    Text(job.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                actionButton
            }
            if job.status.isActive {
                if let progress = job.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            Text(job.statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
        .swipeActions {
            Button(role: .destructive) {
                model.remove(job)
            } label: {
                Label("제거", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .failed: return .red
        case .done: return .green
        default: return .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .converting: Image(systemName: "waveform.circle").foregroundStyle(.purple)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if !job.status.isFinished {
            Button {
                model.cancel(job)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        } else if job.status != .done {
            Button {
                model.retry(job)
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderless)
        } else if let output = job.outputURL {
            ShareLink(item: output) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// iPad 가로 화면에서 입력 화면 옆에 붙는 작업 패널
struct JobsPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.jobs.isEmpty {
                    Text("추출 작업이 여기에 표시됩니다.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.jobs) { job in
                    JobRowView(job: job)
                }
            }
            .listStyle(.plain)
            .navigationTitle("작업")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("완료 항목 지우기") { model.clearFinished() }
                        .disabled(!model.jobs.contains { $0.status.isFinished })
                }
            }
        }
    }
}
