import SwiftUI

/// Wi-Fi가 아닐 때 왜 다운로드가 안 되는지, 언제 시작되는지 알려 준다.
struct NetworkBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let state = model.network.state
        VStack(alignment: .leading, spacing: 8) {
            if let notice = model.networkNotice {
                Label(notice, systemImage: state.allowsDownload ? "wifi" : "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.allowsDownload ? .green : .orange)
            }
            if state == .cellular || state == .offline {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state == .offline ? "인터넷에 연결되어 있지 않습니다" : "Wi-Fi에 연결되어 있지 않습니다")
                            .font(.subheadline.weight(.semibold))
                        Text("YouTube 오디오는 셀룰러 데이터 요금이 나가지 않도록 **Wi-Fi에서만 다운로드**합니다. 지금 추가한 작업은 ‘Wi-Fi 대기’로 보관되고, Wi-Fi에 연결되면 **자동으로 다운로드를 시작**합니다. 받다가 끊긴 파일은 받은 부분부터 이어서 받습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if model.waitingForWiFiCount > 0 {
                            Text("Wi-Fi 대기 중: \(model.waitingForWiFiCount)개")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text("‘파일’ 탭의 다운로드한 영상에서 오디오 추출은 Wi-Fi 없이도 할 수 있습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 보여 줄 내용이 있을 때만 배너를 그린다.
    static func isVisible(_ model: AppModel) -> Bool {
        model.networkNotice != nil || model.network.state == .cellular || model.network.state == .offline
    }
}

/// 전체 다운로드 진행 상황: "3 / 10 완료", 전체 진행 막대, 진행 중·대기·실패 수
struct DownloadSummaryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let summary = model.summary
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("전체 진행")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(summary.done) / \(summary.total) 완료")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: summary.fraction)
                .tint(summary.waiting > 0 && summary.running == 0 ? .orange : .accentColor)
            HStack(spacing: 12) {
                Text(String(format: "%.0f%%", summary.fraction * 100))
                    .font(.caption.monospacedDigit().weight(.semibold))
                if summary.running > 0 {
                    Label("진행 \(summary.running)", systemImage: "arrow.down.circle")
                }
                if summary.queued > 0 {
                    Label("순서 대기 \(summary.queued)", systemImage: "clock")
                }
                if summary.waiting > 0 {
                    Label("Wi-Fi 대기 \(summary.waiting)", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }
                if summary.failed > 0 {
                    Label("실패 \(summary.failed)", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 2)
    }

    static func isVisible(_ model: AppModel) -> Bool {
        model.jobs.contains { !$0.status.isFinished }
    }
}

/// iCloud 파일 한 곡의 받기 상태: 대기 / 받는 중(진행률) / 실패 / 아직 요청 안 함
struct CloudStatusLine: View {
    @ObservedObject private var cloud = CloudDownloadManager.shared
    let url: URL

    var body: some View {
        switch cloud.state(for: url) {
        case .downloading(let progress)?:
            VStack(alignment: .leading, spacing: 3) {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Label(
                    progress.map { String(format: "iCloud에서 받는 중 %.0f%%", $0 * 100) } ?? "iCloud에서 받는 중…",
                    systemImage: "icloud.and.arrow.down"
                )
                .font(.caption)
                .foregroundStyle(.blue)
            }
        case .waitingForWiFi?:
            Label("Wi-Fi 대기 · Wi-Fi에 연결되면 iCloud에서 받습니다", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        case .failed(let message)?:
            Label("iCloud에서 받지 못했습니다: \(message)", systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.red)
        case nil:
            Label("iCloud에만 있음 · 재생하면 Wi-Fi에서 받습니다", systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 보관함 위쪽: iCloud에만 있는 파일 수, 전체 받기 버튼과 진행 상황
struct CloudLibraryBanner: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var cloud = CloudDownloadManager.shared
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud에만 있는 파일 \(model.cloudOnlyCount)개")
                        .font(.subheadline.weight(.semibold))
                    Text("저장 폴더가 iCloud Drive라서 일부 파일은 기기에 내용이 없습니다. 재생하려면 먼저 받아야 하며, **Wi-Fi에서만** 받습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if cloud.downloadingCount > 0 {
                if let progress = cloud.averageProgress {
                    ProgressView(value: progress)
                }
                Text(String(format: "받는 중 %d개 · %.0f%%", cloud.downloadingCount, (cloud.averageProgress ?? 0) * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.blue)
            }
            if cloud.waitingCount > 0 {
                Label("Wi-Fi 대기 \(cloud.waitingCount)개 — Wi-Fi에 연결되면 자동으로 받습니다", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                model.downloadFromCloud(model.library)
            } label: {
                Label(network.state.allowsDownload ? "모두 받기" : "Wi-Fi 연결 시 모두 받기", systemImage: "icloud.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
