import SwiftUI

/// 보관함 노래 정렬 기준 (음악 앱의 '정렬' 메뉴처럼)
enum SongSort: String, CaseIterable, Identifiable {
    case dateAdded, title, folder, size, format

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: return "추가한 날짜"
        case .title: return "제목"
        case .folder: return "폴더"
        case .size: return "크기"
        case .format: return "형식"
        }
    }

    var systemImage: String {
        switch self {
        case .dateAdded: return "calendar"
        case .title: return "textformat"
        case .folder: return "folder"
        case .size: return "internaldrive"
        case .format: return "waveform"
        }
    }

    /// 순서 선택지 이름: (오름차순, 내림차순)
    var orderTitles: (ascending: String, descending: String) {
        switch self {
        case .dateAdded: return ("오래된 순", "최신 순")
        case .title, .folder: return ("가나다 순", "역순")
        case .size: return ("작은 순", "큰 순")
        case .format: return ("가나다 순", "역순")
        }
    }

    func sort(_ items: [LibraryItem], ascending: Bool) -> [LibraryItem] {
        items.sorted { lhs, rhs in
            let result = compare(lhs, rhs)
            if result == .orderedSame {
                // 기준이 같으면 제목으로
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func compare(_ lhs: LibraryItem, _ rhs: LibraryItem) -> ComparisonResult {
        switch self {
        case .dateAdded:
            return lhs.modified == rhs.modified ? .orderedSame : (lhs.modified < rhs.modified ? .orderedAscending : .orderedDescending)
        case .title:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .folder:
            return (lhs.folder ?? "").localizedStandardCompare(rhs.folder ?? "")
        case .size:
            return lhs.size == rhs.size ? .orderedSame : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
        case .format:
            return lhs.url.pathExtension.localizedCaseInsensitiveCompare(rhs.url.pathExtension)
        }
    }
}

/// 폴더 목록 정렬 기준
enum FolderSort: String, CaseIterable, Identifiable {
    case name, recent, count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "이름"
        case .recent: return "최근 추가"
        case .count: return "곡 수"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .recent: return "calendar"
        case .count: return "number"
        }
    }

    var orderTitles: (ascending: String, descending: String) {
        switch self {
        case .name: return ("가나다 순", "역순")
        case .recent: return ("오래된 순", "최신 순")
        case .count: return ("적은 순", "많은 순")
        }
    }
}

/// 툴바의 정렬 메뉴: 기준 + 순서
struct SortMenu<Key: Hashable & Identifiable>: View {
    let keys: [Key]
    @Binding var selection: Key
    @Binding var ascending: Bool
    let title: (Key) -> String
    let systemImage: (Key) -> String
    let orderTitles: (Key) -> (ascending: String, descending: String)

    var body: some View {
        Menu {
            Picker("정렬 기준", selection: $selection) {
                ForEach(keys) { key in
                    Label(title(key), systemImage: systemImage(key)).tag(key)
                }
            }
            Picker("순서", selection: $ascending) {
                Text(orderTitles(selection).ascending).tag(true)
                Text(orderTitles(selection).descending).tag(false)
            }
        } label: {
            Label("정렬: \(title(selection))", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("정렬")
    }
}
