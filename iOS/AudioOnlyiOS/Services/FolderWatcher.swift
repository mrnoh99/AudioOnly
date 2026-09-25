import Foundation

extension Notification.Name {
    /// 저장 폴더의 파일이 (다른 기기의 iCloud 동기화 등으로) 이름이 바뀌거나 옮겨졌을 때.
    /// userInfo: "old" = 이전 URL, "new" = 새 LibraryItem
    static let libraryItemMoved = Notification.Name("AudioOnly.libraryItemMoved")
    /// 대기열에 있던 파일이 사라졌을 때. object: [URL]
    static let libraryItemsRemoved = Notification.Name("AudioOnly.libraryItemsRemoved")
}

/// 저장 폴더를 지켜보다가 파일이 생기거나, 바뀌거나, 이름이 바뀌면 알려 준다.
///
/// iCloud Drive 폴더는 다른 기기에서 한 변경이 동기화되면 파일 조정자(NSFileCoordinator)를 통해
/// 반영되므로, 파일 프레젠터로 등록해 두면 그 변경을 바로 알 수 있다.
final class FolderWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "AudioOnly.FolderWatcher"
        return queue
    }()

    private let onChange: @Sendable () -> Void
    private let onMove: @Sendable (URL, URL) -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void, onMove: @escaping @Sendable (URL, URL) -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        self.onMove = onMove
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        onMove(oldURL, newURL)
        onChange()
    }

    // 삭제는 presentedSubitemDidChange 와 앱의 주기적 새로 읽기로 반영된다.
}
