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

public enum SceneGridDirection: CaseIterable, Sendable {
    case left, right, up, down
}

public enum SceneGridLayout {
    public struct Destination: Equatable, Sendable {
        public let number: Int
        public let column: Int
    }

    private struct Cell {
        let slot: SceneSlot
        let column: Int
        let span: Int

        func distance(to column: Int) -> Int {
            max(self.column - column, column - (self.column + span - 1), 0)
        }
    }

    /// Navigate the rendered rows, retaining the intended column through wide or short rows.
    public static func destination(in slots: [SceneSlot], from number: Int?, direction: SceneGridDirection,
                                   preferredColumn: Int? = nil, includeUnavailable: Bool = false) -> Destination? {
        let grid = rows(for: slots).map { row in
            var column = 0
            return row.slots.enumerated().map { index, slot in
                let span = row.featured && index == 0 ? 2 : 1
                defer { column += span }
                return Cell(slot: slot, column: column, span: span)
            }
        }
        func selectable(_ cell: Cell) -> Bool { includeUnavailable || cell.slot.scene.isAvailable }
        guard let rowIndex = grid.firstIndex(where: { $0.contains(where: { $0.slot.number == number }) }),
              let current = grid[rowIndex].first(where: { $0.slot.number == number }) else {
            guard let first = grid.joined().first(where: selectable) else { return nil }
            return Destination(number: first.slot.number, column: first.column)
        }
        switch direction {
        case .left, .right:
            let candidates = grid[rowIndex].filter {
                selectable($0) && (direction == .left ? $0.column < current.column : $0.column > current.column)
            }
            guard let next = direction == .left ? candidates.last : candidates.first else { return nil }
            let column = direction == .left ? next.column + next.span - 1 : next.column
            return Destination(number: next.slot.number, column: column)
        case .up, .down:
            let column = min(2, max(0, preferredColumn ?? current.column))
            let step = direction == .up ? -1 : 1
            var nextRow = rowIndex + step
            while grid.indices.contains(nextRow) {
                if let next = grid[nextRow].filter(selectable).min(by: { $0.distance(to: column) < $1.distance(to: column) }) {
                    return Destination(number: next.slot.number, column: column)
                }
                nextRow += step
            }
            return nil
        }
    }

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
    /// Move to a visible position, shifting intervening scenes and numbering in reading order.
    public static func moving(_ slots: [SceneSlot], sceneID: String, toPosition position: Int) -> [SceneSlot] {
        guard let source = slots.firstIndex(where: { $0.id == sceneID }),
              slots.indices.contains(position), source != position else { return slots }
        var reordered = slots
        let moved = reordered.remove(at: source)
        reordered.insert(moved, at: position)
        return reordered.enumerated().map { SceneSlot(number: $0.offset + 1, scene: $0.element.scene) }
    }

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
