import Foundation

enum FileStore {
    static let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aac", "caf", "aiff", "flac"]

    /// 앱의 Documents 폴더. '파일' 앱에서 "나의 iPhone > AudioOnly"로 보인다.
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 사진/파일 앱에서 가져온 영상을 잠시 복사해 두는 곳
    static var importsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Imports", isDirectory: true)
    }

    static var downloadsTemporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    private static let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")

    static func sanitize(_ name: String) -> String {
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let noDot = cleaned.hasPrefix(".") ? "_" + String(cleaned.dropFirst()) : cleaned
        return noDot.isEmpty ? "untitled" : String(noDot.prefix(150))
    }

    /// 파일 앱/다른 앱에서 받은 파일을 앱 임시 폴더로 복사한다. (보안 범위 URL 처리 포함)
    static func importCopy(of url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let folder = importsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    static func isTemporaryImport(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(importsDirectory.standardizedFileURL.path)
    }

    /// 임시로 가져온 파일(과 그 UUID 폴더)을 지운다.
    static func removeTemporaryImport(_ url: URL) {
        guard isTemporaryImport(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Documents 아래(하위 폴더 포함)의 오디오 파일 목록, 최신순
    static func libraryItems() -> [LibraryItem] {
        let fm = FileManager.default
        let root = documents.standardizedFileURL
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        var items: [LibraryItem] = []
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let folderPath = url.deletingLastPathComponent().standardizedFileURL.path
            let rootPath = root.path
            let folder = folderPath == rootPath ? nil : String(folderPath.dropFirst(rootPath.count + 1))
            items.append(LibraryItem(
                url: url,
                folder: folder,
                modified: values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0)
            ))
        }
        return items.sorted { $0.modified > $1.modified }
    }
}

struct LibraryItem: Identifiable, Hashable {
    let url: URL
    let folder: String?
    let modified: Date
    let size: Int64

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

/// 동시에 여러 작업이 같은 파일 이름을 고르지 않도록 예약한다.
final class NameReservations: @unchecked Sendable {
    static let shared = NameReservations()

    private let lock = NSLock()
    private var reserved: Set<String> = []

    func reserveUniqueURL(baseName: String, fileExtension: String, in directory: URL) -> URL {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        var index = 0
        while true {
            let name = index == 0 ? baseName : "\(baseName) (\(index))"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
            let path = candidate.standardizedFileURL.path
            if !reserved.contains(path) && !fm.fileExists(atPath: path) {
                reserved.insert(path)
                return candidate
            }
            index += 1
        }
    }

    func release(_ url: URL) {
        lock.lock()
        reserved.remove(url.standardizedFileURL.path)
        lock.unlock()
    }
}
