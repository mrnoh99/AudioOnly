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
