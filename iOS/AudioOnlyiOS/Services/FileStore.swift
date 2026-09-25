import Foundation
import UIKit

extension UIDevice {
    /// '파일' 앱에서 이 기기의 로컬 저장소 이름 ("나의 iPhone" / "나의 iPad")
    static var localStorageName: String {
        current.userInterfaceIdiom == .pad ? "나의 iPad" : "나의 iPhone"
    }
}

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

    /// 받다 만 파일(이어받기용). 임시 폴더와 달리 시스템이 곧바로 지우지 않는 Caches에 둔다.
    static var partialDownloadsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("PartialDownloads", isDirectory: true)
    }

    /// "<key>-<전체 바이트>.part" 형식의 받다 만 파일을 찾는다.
    static func partialDownload(for key: String) -> (url: URL, total: Int64)? {
        let directory = partialDownloadsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        for name in names where name.hasPrefix(key + "-") && name.hasSuffix(".part") {
            let middle = name.dropFirst(key.count + 1).dropLast(".part".count)
            if let total = Int64(middle) {
                return (directory.appendingPathComponent(name), total)
            }
        }
        return nil
    }

    static func removePartialDownloads(for key: String) {
        while let partial = partialDownload(for: key) {
            guard (try? FileManager.default.removeItem(at: partial.url)) != nil else { break }
        }
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

    /// 저장 폴더 아래(하위 폴더 포함)의 오디오 파일 목록, 최신순
    static func libraryItems(in directory: URL) -> [LibraryItem] {
        let fm = FileManager.default
        let root = directory.standardizedFileURL
        let keys: [URLResourceKey] = [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        // iCloud에서 받지 않은 파일(".이름.icloud")도 찾기 위해 숨김 파일을 건너뛰지 않는다.
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return []
        }
        var items: [LibraryItem] = []
        var seen = Set<URL>()
        for case let found as URL in enumerator {
            let values = try? found.resourceValues(forKeys: Set(keys))
            var url = found
            var isCloudOnly = false
            if found.lastPathComponent.hasPrefix(".") {
                guard let real = CloudFiles.realURL(forPlaceholder: found) else {
                    if values?.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                url = real
                isCloudOnly = true
            } else if values?.isUbiquitousItem == true {
                isCloudOnly = values?.ubiquitousItemDownloadingStatus == .notDownloaded
            }
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard isCloudOnly || values?.isRegularFile == true else { continue }
            let key = url.standardizedFileURL
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let folderPath = url.deletingLastPathComponent().standardizedFileURL.path
            let rootPath = root.path
            let folder = folderPath == rootPath ? nil : String(folderPath.dropFirst(rootPath.count + 1))
            items.append(LibraryItem(
                url: key,
                folder: folder,
                modified: values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.fileSize ?? 0),
                isCloudOnly: isCloudOnly
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
    /// iCloud에만 있고 기기에는 아직 받지 않은 파일
    var isCloudOnly = false

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }

    // 같은 파일이면 같은 곡으로 본다(목록을 새로 읽어 수정 시각이 바뀌어도 재생 중 표시 유지).
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
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
