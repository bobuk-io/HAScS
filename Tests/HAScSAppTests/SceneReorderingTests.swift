import Foundation
import XCTest
import HAScSCore
@testable import HAScS

private final class TestCredentials: CredentialStorage {
    var value: Configuration?
    func read() throws -> Configuration? { value }
    func save(_ configuration: Configuration) throws { value = configuration }
}

private actor SceneTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let payload = request.httpMethod == "GET" ? """
        [
          {"entity_id":"scene.charlie","state":"unavailable","attributes":{}},
          {"entity_id":"scene.alpha","state":"unknown","attributes":{}},
          {"entity_id":"scene.beta","state":"unknown","attributes":{}}
        ]
        """ : "[]"
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func captured() -> [URLRequest] { requests }
}

@MainActor
final class SceneReorderingTests: XCTestCase {
    private func fixture() throws -> (SceneStore, UserDefaults, String, SceneTransport) {
        let suite = "io.bobuk.HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set([String: Int](), forKey: "sceneAssignments.v1")
        let storage = TestCredentials()
        storage.value = try Configuration(baseURL: XCTUnwrap(URL(string: "https://mock.invalid")), token: "fake")
        let repository = ConfigurationRepository(storage: storage, defaults: defaults) {
            XCTFail("Must not read legacy credentials")
            throw ConfigurationError.notFound
        }
        let transport = SceneTransport()
        return (SceneStore(defaults: defaults, configuration: repository, transport: transport), defaults, suite, transport)
    }

    func testSavePersistsAndRestoresAcrossStoreAndFetchOrder() async throws {
        let (store, defaults, suite, transport) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        store.beginReordering()
        XCTAssertTrue(store.moveScene("scene.beta", toPosition: 0))
        XCTAssertEqual(store.slots.map(\.id), ["scene.beta", "scene.alpha", "scene.charlie"])
        XCTAssertEqual(store.slots.map(\.number), [1, 2, 3])
        XCTAssertEqual(store.selectedNumber, 1)
        XCTAssertEqual(defaults.dictionary(forKey: "sceneAssignments.v1") as? [String: Int],
                       ["scene.alpha": 1, "scene.beta": 2, "scene.charlie": 3]) // draft only
        store.finishReordering(save: true)
        XCTAssertFalse(store.isReordering)
        let restored = SceneStore(defaults: defaults, configuration: store.configuration, transport: transport)
        await restored.refresh()
        XCTAssertEqual(restored.slots, store.slots)
        let activated = await restored.activate(number: 1)
        XCTAssertTrue(activated)
        let requests = await transport.captured()
        let post = try XCTUnwrap(requests.last)
        XCTAssertEqual(post.httpMethod, "POST")
        let body = try XCTUnwrap(post.httpBody)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["entity_id": "scene.beta"])
    }

    func testEditingBlocksActivationAndRefresh() async throws {
        let (store, defaults, suite, transport) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        store.beginReordering()
        for number in 1...9 {
            let activated = await store.activate(number: number)
            XCTAssertFalse(activated)
        }
        await store.refresh()
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertTrue(store.isReordering)
    }

    func testCancelAndClosingDiscardDraftWithoutSaving() async throws {
        let (store, defaults, suite, _) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        let original = store.slots
        let saved = defaults.dictionary(forKey: "sceneAssignments.v1") as? [String: Int]
        for closeInsteadOfCancel in [false, true] {
            store.beginReordering()
            store.moveScene("scene.charlie", toPosition: 0)
            if closeInsteadOfCancel { store.resetTransientState() }
            else { store.finishReordering(save: false) }
            XCTAssertFalse(store.isReordering)
            XCTAssertEqual(store.slots, original)
            XCTAssertEqual(defaults.dictionary(forKey: "sceneAssignments.v1") as? [String: Int], saved)
        }
    }

    func testKeyboardMovesUnavailableScenesAndStopsAtEdges() async throws {
        let (store, defaults, suite, _) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        XCTAssertFalse(store.moveScene("scene.beta", toPosition: 0)) // not in edit mode
        store.beginReordering()
        store.selectForReordering(3) // unavailable scenes can still be moved
        store.moveSelectedScene(-1)
        store.moveSelectedScene(-1)
        let atStart = store.slots
        store.moveSelectedScene(-1)
        XCTAssertEqual(store.slots, atStart)
        XCTAssertEqual(store.slots.first?.id, "scene.charlie")
        XCTAssertEqual(store.selectedNumber, 1)
        XCTAssertFalse(store.moveScene("scene.foreign", toPosition: 0))
        XCTAssertFalse(store.moveScene("scene.alpha", toPosition: 99))
        store.moveSelection(1)
        XCTAssertEqual(store.selectedNumber, 2)
        store.finishReordering(save: true)
        XCTAssertEqual(store.selectedNumber, 2)
    }

    func testConfigurationChangeDiscardsEditingState() async throws {
        let (store, defaults, suite, _) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        store.beginReordering()
        store.moveScene("scene.beta", toPosition: 0)
        store.invalidateConfiguration()
        XCTAssertFalse(store.isReordering)
        XCTAssertTrue(store.slots.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.slots.first?.id, "scene.alpha")
    }
}
