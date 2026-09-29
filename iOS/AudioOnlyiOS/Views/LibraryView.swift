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
    // 정렬 설정은 앱을 다시 켜도 유지된다.
    @AppStorage("library.songSort") private var songSort: SongSort = .dateAdded
    @AppStorage("library.songAscending") private var songAscending = false
    @AppStorage("library.folderSort") private var folderSort: FolderSort = .name
    @AppStorage("library.folderAscending") private var folderAscending = true

    /// 검색어로 거른 뒤 선택한 기준으로 정렬한 노래. 곡을 누르면 이 순서대로 재생한다.
    private var filteredLibrary: [LibraryItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let matched = text.isEmpty ? model.library : model.library.filter {
            $0.name.localizedCaseInsensitiveContains(text) || ($0.folder ?? "").localizedCaseInsensitiveContains(text)
        }
        return songSort.sort(matched, ascending: songAscending)
    }

    struct FolderGroup: Identifiable {
        let name: String
        let items: [LibraryItem]
        var id: String { name }
    }

    /// 폴더(재생목록)별 묶음. 저장 폴더 바로 아래 파일은 '기타'.
    private func folders(from songs: [LibraryItem]) -> [FolderGroup] {
        let groups = Dictionary(grouping: songs) { $0.folder ?? "" }
        return groups
            .map { key, value in
                FolderGroup(name: key, items: value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
            .sorted { lhs, rhs in
                // '기타'(저장 폴더 바로 아래 파일)는 항상 맨 뒤
                if lhs.name.isEmpty != rhs.name.isEmpty { return !lhs.name.isEmpty }
                let result: ComparisonResult
                switch folderSort {
                case .name:
                    result = lhs.name.localizedStandardCompare(rhs.name)
                case .recent:
                    let l = lhs.items.map(\.modified).max() ?? .distantPast
                    let r = rhs.items.map(\.modified).max() ?? .distantPast
                    result = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
                case .count:
                    result = lhs.items.count == rhs.items.count
                        ? .orderedSame
                        : (lhs.items.count < rhs.items.count ? .orderedAscending : .orderedDescending)
                }
                if result == .orderedSame {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return folderAscending ? result == .orderedAscending : result == .orderedDescending
            }
    }

    var body: some View {
        // 정렬은 화면을 그릴 때 한 번만 한다(행마다 다시 정렬하면 곡이 많을 때 매우 느려진다).
        let songs = filteredLibrary
        NavigationStack {
            List {
                if NetworkBanner.isVisible(model) {
                    Section { NetworkBanner() }
                }
                if !model.jobs.isEmpty {
                    Section {
                        if DownloadSummaryView.isVisible(model) {
                            DownloadSummaryView()
                        }
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
                    if model.cloudOnlyCount > 0 {
                        Section { CloudLibraryBanner() }
                    }
                    Section {
                        PlayShuffleButtons(items: songs)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    }
                    Section("노래 \(songs.count)곡") {
                        ForEach(songs) { item in
                            LibraryRowView(item: item, playlist: songs, onDelete: delete)
                                // iPad: 다른 앱(파일, 메일, GarageBand …)으로 끌어다 놓기
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        }
                        .onDelete { offsets in
                            delete(offsets.map { songs[$0] })
                        }
                    }
                } else {
                    let groups = folders(from: songs)
                    Section("폴더 \(groups.count)개") {
                        ForEach(groups) { folder in
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if mode == .songs {
                        SortMenu(
                            keys: SongSort.allCases,
                            selection: $songSort,
                            ascending: $songAscending,
                            title: \.title,
                            systemImage: \.systemImage,
                            orderTitles: \.orderTitles
                        )
                    } else {
                        SortMenu(
                            keys: FolderSort.allCases,
                            selection: $folderSort,
                            ascending: $folderAscending,
                            title: \.title,
                            systemImage: \.systemImage,
                            orderTitles: \.orderTitles
                        )
                    }
                }
            }
            .refreshable { model.refreshLibrary() }
            .onAppear { model.refreshLibrary() }
            // 목록 끝이 미니 플레이어에 가려지지 않도록 목록에 직접 붙인다.
            .safeAreaInset(edge: .bottom, spacing: 0) { BottomPlayerBars() }
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

    // 폴더 안에서는 기본으로 제목(번호) 순 — 재생목록 순서가 유지된다.
    @AppStorage("library.folderSongSort") private var sort: SongSort = .title
    @AppStorage("library.folderSongAscending") private var ascending = true

    private var items: [LibraryItem] {
        sort.sort(model.library.filter { ($0.folder ?? "") == folder }, ascending: ascending)
    }

    var body: some View {
        let items = self.items
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
                    delete(offsets.map { items[$0] })
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { BottomPlayerBars() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SortMenu(
                    keys: SongSort.allCases.filter { $0 != .folder },
                    selection: $sort,
                    ascending: $ascending,
                    title: \.title,
                    systemImage: \.systemImage,
                    orderTitles: \.orderTitles
                )
            }
        }
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
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: LibraryItem
    /// 이 곡을 눌렀을 때 대기열이 될 목록
    let playlist: [LibraryItem]
    var onDelete: ([LibraryItem]) -> Void = { _ in }

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var renameError: String?
    @State private var isBoosting = false

    private var isCurrent: Bool { player.current == item }

    var body: some View {
        Button {
            player.select(item, in: playlist)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    FileArtworkView(url: item.url, size: 48)
                        .opacity(item.isCloudOnly ? 0.5 : 1)
                    if item.isCloudOnly && !isCurrent {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
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
                    if item.isCloudOnly {
                        CloudStatusLine(url: item.url)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isCloudOnly {
                Button {
                    CloudDownloadManager.shared.request([item.url], priority: true)
                } label: {
                    Label("iCloud에서 받기 (Wi-Fi)", systemImage: "icloud.and.arrow.down")
                }
            }
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
            Button {
                newName = item.name
                isRenaming = true
            } label: {
                Label("이름 변경", systemImage: "pencil")
            }
            Button {
                isBoosting = true
            } label: {
                Label("음량 올리기", systemImage: "speaker.plus")
            }
            .disabled(item.isCloudOnly)
            Button(role: .destructive) {
                onDelete([item])
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .alert("이름 변경", isPresented: $isRenaming) {
            TextField("파일 이름", text: $newName)
                .autocorrectionDisabled()
            Button("취소", role: .cancel) {}
            Button("저장") { rename() }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("확장자(.\(item.url.pathExtension))는 그대로 유지됩니다.")
        }
        .sheet(isPresented: $isBoosting) {
            VolumeBoostSheet(item: item)
        }
        .alert(
            "이름을 바꿀 수 없습니다",
            isPresented: Binding(get: { renameError != nil }, set: { if !$0 { renameError = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(renameError ?? "")
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

extension LibraryRowView {
    fileprivate func rename() {
        do {
            let renamed = try model.rename(item, to: newName)
            player.itemRenamed(from: item, to: renamed)
        } catch {
            renameError = error.localizedDescription
        }
    }
}

/// 파일의 음량을 몇 % 올릴지 고르고 저장한다.
struct VolumeBoostSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem

    @AppStorage("library.volumeBoostPercent") private var percent = 50.0
    @State private var progress: Double?
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    private static let presets: [Double] = [10, 25, 50, 100, 200]

    private var gainText: String {
        let gain = 1 + percent / 100
        let decibels = 20 * log10(gain)
        return String(format: "원래 소리의 %g배 (+%.1f dB)", gain, decibels)
    }

    private var isWorking: Bool { progress != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name).lineLimit(2)
                }
                Section {
                    HStack {
                        Text("올릴 음량")
                        Spacer()
                        Text("+\(Int(percent))%")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    Slider(value: $percent, in: 10...300, step: 5)
                    HStack {
                        ForEach(Self.presets, id: \.self) { value in
                            Button("\(Int(value))%") { percent = value }
                                .buttonStyle(.bordered)
                                .tint(percent == value ? Color.accentColor : Color.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.caption)
                } footer: {
                    Text(footerText)
                }
                .disabled(isWorking)

                if let progress {
                    Section {
                        ProgressView(value: progress) { Text("저장 중…") }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("음량 올리기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        task?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { start() }
                        .disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
        .presentationDetents([.medium, .large])
    }

    private var footerText: String {
        let ext = item.url.pathExtension.lowercased()
        let target = ext == "m4a" || ext == "wav"
            ? "이 파일에 바로 저장합니다."
            : "\(ext.uppercased()) 파일은 같은 이름의 M4A 파일로 바꿔 저장합니다."
        return "\(gainText). \(target) 너무 크게 올리면 큰 소리 부분이 잘려 찌그러질 수 있습니다."
    }

    private func start() {
        errorText = nil
        progress = 0
        let percent = Int(percent)
        task = Task {
            do {
                let updated = try await model.boostVolume(item, percent: percent) { value in
                    Task { @MainActor in progress = max(progress ?? 0, value) }
                }
                if updated.url != item.url {
                    player.itemRenamed(from: item, to: updated)
                }
                dismiss()
            } catch is CancellationError {
                progress = nil
            } catch {
                progress = nil
                errorText = error.localizedDescription
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
            } else if job.status == .waitingForWiFi, let progress = job.progress, progress > 0 {
                // 받다가 멈춘 만큼 표시
                ProgressView(value: progress).tint(.orange)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(job.statusText)
                    .foregroundStyle(statusColor)
                    .lineLimit(3)
                Spacer(minLength: 4)
                if job.status == .downloading, let bytes = job.bytesText {
                    Text(bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
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
        case .waitingForWiFi: return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .waitingForWiFi: Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
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
                if NetworkBanner.isVisible(model) {
                    NetworkBanner()
                }
                if DownloadSummaryView.isVisible(model) {
                    DownloadSummaryView()
                }
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
