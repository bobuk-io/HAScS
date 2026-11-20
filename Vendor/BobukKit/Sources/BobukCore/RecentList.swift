// Most-recent-first list with case-insensitive de-duplication and a limit, from lowkey's input
// history. Ranking and display stay with the app.
import Foundation

public struct RecentList: Codable, Equatable, Sendable {
    public private(set) var entries: [String]
    public var limit: Int

    public init(entries: [String] = [], limit: Int = 1000) {
        self.limit = limit
        self.entries = []
        for entry in entries.reversed() { record(entry) }
    }

    /// Moves `entry` to the front (trimmed); an empty entry is ignored. Duplicates differ only
    /// in letter case, the newest spelling wins.
    public mutating func record(_ entry: String) {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        entries.insert(text, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(_ entry: String) {
        entries.removeAll { $0.caseInsensitiveCompare(entry) == .orderedSame }
    }

    public mutating func removeAll() { entries.removeAll() }

    public func contains(_ entry: String) -> Bool {
        entries.contains { $0.caseInsensitiveCompare(entry) == .orderedSame }
    }

    private enum CodingKeys: String, CodingKey { case entries, limit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 1000
        self.init(entries: try container.decodeIfPresent([String].self, forKey: .entries) ?? [], limit: limit)
    }
}
