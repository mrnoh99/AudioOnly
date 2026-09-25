import Foundation
import Network

enum NetworkState: Equatable {
    case unknown, wifi, cellular, offline

    /// YouTube 다운로드는 Wi-Fi(또는 유선)에서만 한다. 셀룰러 데이터 요금이 나가지 않도록.
    var allowsDownload: Bool { self == .wifi }

    var title: String {
        switch self {
        case .unknown: return "확인 중"
        case .wifi: return "Wi-Fi"
        case .cellular: return "셀룰러 데이터"
        case .offline: return "연결 없음"
        }
    }
}

/// 현재 네트워크가 Wi-Fi인지 감시한다.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var state: NetworkState = .unknown
    var onChange: ((_ old: NetworkState, _ new: NetworkState) -> Void)?

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newState: NetworkState
            if path.status != .satisfied {
                newState = .offline
            } else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                newState = .wifi
            } else {
                newState = .cellular
            }
            Task { @MainActor in self?.update(newState) }
        }
        monitor.start(queue: DispatchQueue(label: "AudioOnly.network"))
    }

    deinit {
        monitor.cancel()
    }

    private func update(_ newState: NetworkState) {
        guard newState != state else { return }
        let old = state
        state = newState
        onChange?(old, newState)
    }
}
