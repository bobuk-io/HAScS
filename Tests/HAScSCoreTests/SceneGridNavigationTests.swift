import Foundation
import XCTest
@testable import HAScSCore

final class SceneGridNavigationTests: XCTestCase {
    private func slots(count: Int = 9, unavailable: Set<Int> = []) throws -> [SceneSlot] {
        try (0..<count).map { index in
            let number = index + 1
            let object: [String: Any] = ["entity_id": "scene.item_\(number)",
                                         "state": unavailable.contains(number) ? "unavailable" : "unknown",
                                         "attributes": [:]]
            let scene = try JSONDecoder().decode(HAScene.self, from: JSONSerialization.data(withJSONObject: object))
            return SceneSlot(number: number, scene: scene)
        }
    }

    func testArrowsFollowRowsAndColumnsWithoutWrapping() throws {
        let slots = try slots()
        let cases: [(Int, SceneGridDirection, Int?)] = [
            (1, .left, nil), (1, .right, 2), (2, .left, 1), (2, .right, nil),
            (3, .left, nil), (3, .right, 4), (4, .right, 5), (5, .right, nil),
            (1, .down, 3), (2, .down, 5), (3, .down, 6), (4, .down, 7), (5, .down, 8),
            (6, .down, 9), (7, .down, 9), (8, .down, 9), (9, .down, nil),
            (1, .up, nil), (2, .up, nil), (3, .up, 1), (4, .up, 1), (5, .up, 2),
            (6, .up, 3), (7, .up, 4), (8, .up, 5), (9, .up, 6),
        ]
        for (from, direction, expected) in cases {
            XCTAssertEqual(SceneGridLayout.destination(in: slots, from: from, direction: direction)?.number,
                           expected, "\(from) / \(direction)")
        }
    }

    func testVerticalRoundTripsRememberColumnThroughWideAndShortRows() throws {
        let slots = try slots()
        let up = try XCTUnwrap(SceneGridLayout.destination(in: slots, from: 4, direction: .up))
        XCTAssertEqual(up.number, 1)
        XCTAssertEqual(up.column, 1)
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: up.number, direction: .down,
                                                   preferredColumn: up.column)?.number, 4)
        let down = try XCTUnwrap(SceneGridLayout.destination(in: slots, from: 8, direction: .down))
        XCTAssertEqual(down.number, 9)
        XCTAssertEqual(down.column, 2)
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: down.number, direction: .up,
                                                   preferredColumn: down.column)?.number, 8)
    }

    func testHorizontalMovementResetsColumnAtWideTileEdge() throws {
        let slots = try slots()
        let left = try XCTUnwrap(SceneGridLayout.destination(in: slots, from: 2, direction: .left))
        XCTAssertEqual(left.number, 1)
        XCTAssertEqual(left.column, 1)
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: 1, direction: .down,
                                                   preferredColumn: left.column)?.number, 4)
    }

    func testUnavailableScenesAreSkippedWithoutCollapsingGeometry() throws {
        let slots = try slots(unavailable: [4, 5])
        XCTAssertNil(SceneGridLayout.destination(in: slots, from: 3, direction: .right))
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: 2, direction: .down)?.number, 3)
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: 2, direction: .down,
                                                   includeUnavailable: true)?.number, 5)
        let emptyRow = try self.slots(unavailable: [3, 4, 5])
        XCTAssertEqual(SceneGridLayout.destination(in: emptyRow, from: 2, direction: .down)?.number, 8)
    }

    func testGeometryUsesPositionsNotPossiblySparseSceneNumbers() throws {
        let original = try slots(count: 4)
        let sparse = zip([2, 4, 7, 9], original).map { SceneSlot(number: $0.0, scene: $0.1.scene) }
        XCTAssertEqual(SceneGridLayout.destination(in: sparse, from: 2, direction: .down)?.number, 7)
        XCTAssertEqual(SceneGridLayout.destination(in: sparse, from: 4, direction: .down)?.number, 9)
        XCTAssertEqual(SceneGridLayout.destination(in: sparse, from: 9, direction: .up)?.number, 2)
    }

    func testEmptySingleAndMissingSelectionAreSafe() throws {
        for direction in SceneGridDirection.allCases {
            XCTAssertNil(SceneGridLayout.destination(in: [], from: nil, direction: direction))
            XCTAssertNil(SceneGridLayout.destination(in: try slots(count: 1), from: 1, direction: direction))
        }
        let slots = try slots(count: 3, unavailable: [1, 2])
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: nil, direction: .down)?.number, 3)
        XCTAssertEqual(SceneGridLayout.destination(in: slots, from: 99, direction: .up)?.number, 3)
        let unavailable = try self.slots(count: 3, unavailable: [1, 2, 3])
        XCTAssertNil(SceneGridLayout.destination(in: unavailable, from: nil, direction: .down))
        XCTAssertEqual(SceneGridLayout.destination(in: unavailable, from: nil, direction: .down,
                                                   includeUnavailable: true)?.number, 1)
    }
}
