import AppKit
import SwiftUI

struct JobListView: View {
    @EnvironmentObject private var queue: JobQueue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("작업 목록").font(.headline)
                Text("\(queue.jobs.count)").foregroundStyle(.secondary)
                Spacer()
                Button("모두 취소") { queue.cancelAll() }
                    .disabled(queue.jobs.isEmpty)
                Button("완료 항목 지우기") { queue.clearFinished() }
                    .disabled(queue.jobs.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if queue.jobs.isEmpty {
                Text("추출 작업이 여기에 표시됩니다.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.jobs) { job in
                    JobRowView(job: job)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

struct JobRowView: View {
    @EnvironmentObject private var queue: JobQueue
    @ObservedObject var job: Job
    @State private var showLog = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title).lineLimit(1)
                Group {
                    if case .failed(let reason) = job.status {
                        Text(reason).foregroundStyle(.red)
                    } else if let output = job.outputURL, job.status == .done {
                        Text(output.path)
                    } else {
                        Text(job.sourceDescription)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

                if job.status.isActive {
                    if let progress = job.progress, job.status == .running {
                        ProgressView(value: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(job.statusText)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            actions
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("로그 보기") { showLog = true }
            Button("목록에서 제거") { queue.remove(job) }
        }
        .popover(isPresented: $showLog) {
            ScrollView {
                Text(job.log.isEmpty ? "(로그 없음)" : job.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(width: 560, height: 320)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .converting:
            Image(systemName: "waveform.circle").foregroundStyle(.purple)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if job.status == .done, let output = job.outputURL {
                iconButton("play.circle", help: "재생") {
                    NSWorkspace.shared.open(output)
                }
                iconButton("magnifyingglass.circle", help: "Finder에서 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
            }
            if job.status.isFinished && job.status != .done {
                iconButton("arrow.clockwise.circle", help: "다시 시도") { queue.retry(job) }
            }
            if !job.status.isFinished {
                iconButton("xmark.circle", help: "취소") { queue.cancel(job) }
            }
            iconButton("doc.text", help: "로그 보기") { showLog = true }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.title3)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
