import SwiftUI

/// 진행 중인 작업과 추출된 오디오 파일 목록
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var player: AudioPlayer

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

                Section("저장된 오디오 \(model.library.count)개") {
                    if model.library.isEmpty {
                        Text("아직 추출한 오디오가 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.library) { item in
                        LibraryRowView(item: item)
                    }
                    .onDelete { offsets in
                        let items = offsets.map { model.library[$0] }
                        if let current = player.current, items.contains(current) {
                            player.stop()
                        }
                        model.delete(items)
                    }
                }
            }
            .navigationTitle("보관함")
            .refreshable { model.refreshLibrary() }
            .onAppear { model.refreshLibrary() }
            .safeAreaInset(edge: .bottom) {
                if player.current != nil {
                    MiniPlayerView()
                }
            }
        }
    }
}

struct LibraryRowView: View {
    @EnvironmentObject private var player: AudioPlayer
    let item: LibraryItem

    private var isCurrent: Bool { player.current == item }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.play(item)
            } label: {
                Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.url.pathExtension.uppercased())
                    Text(item.sizeText)
                    if let folder = item.folder {
                        Label(folder, systemImage: "folder").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            ShareLink(item: item.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
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

struct MiniPlayerView: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        if let item = player.current {
            VStack(spacing: 6) {
                HStack {
                    Text(item.name).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 1)
                )
                HStack {
                    Text(format(player.currentTime))
                    Spacer()
                    Text(format(player.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
