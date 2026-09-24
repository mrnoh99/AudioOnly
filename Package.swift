// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioOnly",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "AudioOnly",
            path: "Sources/AudioOnly",
            // 앱 아이콘은 Xcode 프로젝트와 build-app.sh(.icns 생성)에서 사용한다.
            exclude: ["Assets.xcassets"]
        )
    ]
)
