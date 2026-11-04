import Foundation

public struct HAScene: Identifiable, Decodable, Equatable, Sendable {
    public struct Attributes: Decodable, Equatable, Sendable {
        public let friendlyName: String?
        public let icon: String?
        enum CodingKeys: String, CodingKey { case friendlyName = "friendly_name", icon }
    }
    public let entityID: String
    public let state: String
    public let attributes: Attributes
    public var id: String { entityID }
    public var name: String { attributes.friendlyName?.isEmpty == false ? attributes.friendlyName! : String(entityID.dropFirst("scene.".count)).replacingOccurrences(of: "_", with: " ") }
    public var isAvailable: Bool { state != "unavailable" }
    enum CodingKeys: String, CodingKey { case entityID = "entity_id", state, attributes }
}

public struct SceneSlot: Identifiable, Equatable, Sendable {
    public let number: Int
    public let scene: HAScene
    public var id: String { scene.id }
    public init(number: Int, scene: HAScene) { self.number = number; self.scene = scene }
}

public struct SceneGridRow: Identifiable, Equatable, Sendable {
    public let slots: [SceneSlot]
    public let featured: Bool
    public var id: String { slots[0].id }
}

public enum SceneGridLayout {
    public static func rows(for slots: [SceneSlot]) -> [SceneGridRow] {
        guard !slots.isEmpty else { return [] }
        var rows = [SceneGridRow(slots: Array(slots.prefix(2)), featured: true)]
        var rest = Array(slots.dropFirst(2))
        while !rest.isEmpty {
            rows.append(SceneGridRow(slots: Array(rest.prefix(3)), featured: false))
            rest.removeFirst(min(3, rest.count))
        }
        return rows
    }
}

/// Retain existing assignments as entities are added or removed; free slots can be reused.
public enum SceneAssignments {
    public static func assign(scenes: [HAScene], previous: [String: Int]) -> [SceneSlot] {
        let sorted = scenes.sorted { $0.entityID.localizedStandardCompare($1.entityID) == .orderedAscending }
        var used = Set<Int>()
        var assigned: [SceneSlot] = []
        var pending: [HAScene] = []
        for scene in sorted {
            if let number = previous[scene.id], (1...9).contains(number), used.insert(number).inserted {
                assigned.append(SceneSlot(number: number, scene: scene))
            } else {
                pending.append(scene)
            }
        }
        for scene in pending {
            guard let number = (1...9).first(where: { !used.contains($0) }) else { break }
            used.insert(number)
            assigned.append(SceneSlot(number: number, scene: scene))
        }
        return assigned.sorted { $0.number < $1.number }
    }
}
