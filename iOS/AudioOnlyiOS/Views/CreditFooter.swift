import SwiftUI

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    static var credit: String {
        "Developed by JaiSung NOH MD 2026. version \(version) build \(build)"
    }
}

/// 모든 화면 맨 아래의 작은 제작자 표시
struct CreditFooter: View {
    var body: some View {
        Text(AppInfo.credit)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .accessibilityLabel(AppInfo.credit)
    }
}
