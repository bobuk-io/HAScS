import XCTest
import Security
@testable import HAScSCore

private actor MockTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let status: Int
    let payload: Data
    init(status: Int = 200, payload: String = "[]") {
        self.status = status
        self.payload = Data(payload.utf8)
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func firstRequest() -> URLRequest? { requests.first }
}

private final class MemoryCredentialStorage: CredentialStorage {
    var value: Configuration?
    var readError: Error?
    var saveError: Error?
    var writes = 0
    func read() throws -> Configuration? {
        if let readError { throw readError }
        return value
    }
    func save(_ configuration: Configuration) throws {
        if let saveError { throw saveError }
        writes += 1
        value = configuration
    }
}

final class HAScSCoreTests: XCTestCase {
    private func scene(_ id: String, name: String? = nil, state: String = "unknown") throws -> HAScene {
        let attributes = name.map { ["friendly_name": $0] } ?? [:]
        let object: [String: Any] = ["entity_id": "scene.\(id)", "state": state, "attributes": attributes]
        return try JSONDecoder().decode(HAScene.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testConfigurationParsingAndSecurity() throws {
        let config = try Configuration.parse("# test\nexport HA_URL = 'https://example.com/ha/'\nHA_TOKEN=\"a=b\"\nOTHER=ignore\n")
        XCTAssertEqual(config.baseURL.absoluteString, "https://example.com/ha/")
        XCTAssertEqual(config.token, "a=b")
        XCTAssertThrowsError(try Configuration.parse("HA_URL=https://example.com"))
        XCTAssertThrowsError(try Configuration.parse("HA_URL=file:///etc/passwd\nHA_TOKEN=abc"))
        XCTAssertThrowsError(try Configuration.parse("HA_URL=https://user:pass@example.com\nHA_TOKEN=abc"))
        XCTAssertThrowsError(try Configuration.parse("HA_URL=https://example.com/?x=1\nHA_TOKEN=abc"))
        XCTAssertThrowsError(try Configuration.parse("HA_URL=https://example.com\nHA_TOKEN=\"\""))
    }

    func testExplicitMissingConfigurationDoesNotFallback() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/HAScS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try "HA_URL=https://example.com\nHA_TOKEN=abc".write(to: home.appendingPathComponent(".config/HAScS/.env"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Configuration.loadLegacy(environment: ["HASCS_ENV_FILE": "/not/a/real/file"], home: home))
        XCTAssertEqual(try Configuration.loadLegacy(environment: [:], home: home).baseURL.host, "example.com")
    }

    func testMigrationImportsOnlyOnceAndUsesSecureStorage() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MemoryCredentialStorage()
        let old = try Configuration.parse("HA_URL=https://old.example\nHA_TOKEN=old")
        let changed = try Configuration.parse("HA_URL=https://new.example\nHA_TOKEN=new")
        var imports = 0
        let repo = ConfigurationRepository(storage: storage, defaults: defaults) { imports += 1; return old }
        XCTAssertEqual(try repo.load(), old)
        XCTAssertEqual(storage.writes, 1)
        XCTAssertEqual(imports, 1)
        try repo.save(changed)
        XCTAssertEqual(try repo.load(), changed)
        XCTAssertEqual(imports, 1)
        storage.value = nil // deletion never silently reimports the original token
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(imports, 1)
    }

    func testKeychainFailureNeverFallsBackToPlaintext() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MemoryCredentialStorage()
        storage.readError = CredentialError.keychain(-1)
        var imports = 0
        let repo = ConfigurationRepository(storage: storage, defaults: defaults) {
            imports += 1
            return try Configuration.parse("HA_URL=https://old.example\nHA_TOKEN=old")
        }
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(imports, 0)
        storage.readError = nil
        storage.saveError = CredentialError.keychain(-1)
        XCTAssertThrowsError(try repo.load())
        XCTAssertEqual(imports, 1)
        XCTAssertNil(storage.value)
        storage.saveError = nil
        _ = try repo.load()
        XCTAssertEqual(imports, 2) // failed writes do not mark migration complete
    }

    func testExistingKeychainCredentialsTakePrecedence() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MemoryCredentialStorage()
        storage.value = try Configuration.parse("HA_URL=https://new.example\nHA_TOKEN=new")
        let repo = ConfigurationRepository(storage: storage, defaults: defaults) {
            XCTFail("Legacy configuration must not be read")
            throw ConfigurationError.notFound
        }
        XCTAssertEqual(try repo.load().baseURL.host, "new.example")
    }

    func testIdentifierMigrationPrefersOldKeychainOverEnv() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let current = MemoryCredentialStorage()
        let old = MemoryCredentialStorage()
        old.value = try Configuration.parse("HA_URL=https://keychain.example\nHA_TOKEN=old")
        let repository = ConfigurationRepository(storage: current, defaults: defaults, legacyStorage: old) {
            XCTFail("Should not read stale plaintext configuration")
            throw ConfigurationError.notFound
        }
        XCTAssertEqual(try repository.load().baseURL.host, "keychain.example")
        XCTAssertEqual(current.value, old.value)
        XCTAssertEqual(current.writes, 1)
        XCTAssertEqual(try repository.load().baseURL.host, "keychain.example")
        XCTAssertEqual(current.writes, 1)
        XCTAssertNotNil(old.value) // Migration leaves the backup untouched.
    }

    func testIdentifierMigrationKeychainFailureNeverReadsEnv() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let current = MemoryCredentialStorage()
        let old = MemoryCredentialStorage()
        old.readError = CredentialError.keychain(-1)
        var envReads = 0
        let repository = ConfigurationRepository(storage: current, defaults: defaults, legacyStorage: old) {
            envReads += 1
            return try Configuration.parse("HA_URL=https://stale.example\nHA_TOKEN=old")
        }
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(envReads, 0)
        XCTAssertNil(current.value)
    }

    func testMissingOldKeychainDoesNotResurrectStaleEnv() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let oldSuite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        defer { defaults.removePersistentDomain(forName: suite); oldDefaults.removePersistentDomain(forName: oldSuite) }
        oldDefaults.set(true, forKey: "credentials.migrated.v1")
        var envReads = 0
        let repository = ConfigurationRepository(storage: MemoryCredentialStorage(), defaults: defaults,
                                                 legacyStorage: MemoryCredentialStorage(), legacyDefaults: oldDefaults) {
            envReads += 1
            return try Configuration.parse("HA_URL=https://stale.example\nHA_TOKEN=old")
        }
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(envReads, 0)
    }

    func testSceneAssignmentsMoveOnceWithoutOverwriting() throws {
        let suite = "HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "sceneAssignments.v1"
        IdentifierMigration.migrateSceneAssignments(to: defaults, from: [key: ["scene.one": 4]])
        XCTAssertEqual(defaults.dictionary(forKey: key) as? [String: Int], ["scene.one": 4])
        defaults.set(["scene.two": 5], forKey: key)
        IdentifierMigration.migrateSceneAssignments(to: defaults, from: [key: ["scene.one": 4]])
        XCTAssertEqual(defaults.dictionary(forKey: key) as? [String: Int], ["scene.two": 5])
    }

    func testAssignmentsAreStableAndBounded() throws {
        let a = try scene("alpha"), b = try scene("beta"), c = try scene("charlie")
        let first = SceneAssignments.assign(scenes: [c, a, b], previous: [:])
        XCTAssertEqual(first.map(\.id), ["scene.alpha", "scene.beta", "scene.charlie"])
        let previous = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0.number) })
        let updated = SceneAssignments.assign(scenes: [c, try scene("aardvark"), b], previous: previous)
        XCTAssertEqual(updated.map(\.id), ["scene.aardvark", "scene.beta", "scene.charlie"])
        XCTAssertEqual(updated.first(where: { $0.id == "scene.beta" })?.number, 2)
        let many = try (0..<12).map { try scene("item_\($0)") }
        XCTAssertEqual(SceneAssignments.assign(scenes: many, previous: [:]).count, 9)
        let invalid = SceneAssignments.assign(scenes: [a, b, c], previous: [a.id: 2, b.id: 2, c.id: 99])
        XCTAssertEqual(Set(invalid.map(\.number)).count, 3)
    }

    func testGridLayoutForAdditionalScenes() throws {
        let scenes = try (1...10).map { try scene("item_\($0)") }
        for (total, expected) in [(6, [2, 3, 1]), (7, [2, 3, 2]), (10, [2, 3, 3, 1])] {
            let slots = SceneAssignments.assign(scenes: Array(scenes.prefix(total)), previous: [:])
            let rows = SceneGridLayout.rows(for: slots)
            XCTAssertEqual(rows.map { $0.slots.count }, expected)
            XCTAssertEqual(rows.flatMap(\.slots).count, min(total, 9))
            XCTAssertTrue(rows[0].featured)
            XCTAssertTrue(rows.dropFirst().allSatisfy { !$0.featured })
        }
        XCTAssertTrue(SceneGridLayout.rows(for: []).isEmpty)
    }

    func testSceneFallbackAndAvailability() throws {
        let unknown = try scene("movie_time")
        XCTAssertEqual(unknown.name, "movie time")
        XCTAssertTrue(unknown.isAvailable) // A never-activated scene may be unknown.
        XCTAssertFalse(try scene("x", state: "unavailable").isAvailable)
    }

    func testFetchFiltersUnrelatedEntitiesAndUsesAuth() async throws {
        let transport = MockTransport(payload: """
        [{"entity_id":"light.test"},{"entity_id":"scene.night","state":"unknown","attributes":{"friendly_name":"night"}}]
        """)
        let config = try Configuration.parse("HA_URL=https://example.com/ha\nHA_TOKEN=secret")
        let result = try await HomeAssistantClient(configuration: config, transport: transport).fetchScenes()
        XCTAssertEqual(result.map(\.name), ["night"])
        let request = await transport.firstRequest()
        XCTAssertEqual(request?.url?.absoluteString, "https://example.com/ha/api/states")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testActivationUsesCorrectServiceAndEntity() async throws {
        let transport = MockTransport()
        let config = try Configuration.parse("HA_URL=https://example.com\nHA_TOKEN=secret")
        let client = HomeAssistantClient(configuration: config, transport: transport)
        try await client.activate(sceneID: "scene.night")
        let captured = await transport.firstRequest()
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.path, "/api/services/scene/turn_on")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["entity_id": "scene.night"])
    }

    func testKeychainRoundTripWhenConfigured() throws {
        guard ProcessInfo.processInfo.environment["HASCS_TEST_KEYCHAIN"] == "1" else {
            throw XCTSkip("Set HASCS_TEST_KEYCHAIN=1 to test a temporary Keychain item")
        }
        let service = "io.bobuk.HAScS.tests.\(UUID().uuidString)"
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service,
                           kSecAttrAccount as String: "home-assistant-connection",
                           kSecAttrSynchronizable as String: false] as CFDictionary)
        }
        let store = KeychainCredentialStore(service: service)
        XCTAssertNil(try store.read())
        let first = try Configuration.parse("HA_URL=https://one.example\nHA_TOKEN=fake-token")
        let second = try Configuration.parse("HA_URL=https://two.example\nHA_TOKEN=another-fake-token")
        try store.save(first)
        XCTAssertEqual(try store.read(), first)
        try store.save(second)
        XCTAssertEqual(try store.read(), second)
    }

    func testLoopbackIntegrationWhenConfigured() async throws {
        guard let value = ProcessInfo.processInfo.environment["HASCS_TEST_MOCK_URL"] else {
            throw XCTSkip("Set HASCS_TEST_MOCK_URL to a loopback mock server")
        }
        let url = try XCTUnwrap(URL(string: value))
        guard url.scheme == "http", url.host == "127.0.0.1" || url.host == "localhost" else {
            XCTFail("Integration tests must only target a local mock server")
            return
        }
        let config = try Configuration(baseURL: url, token: "not-a-secret")
        let client = HomeAssistantClient(configuration: config)
        let scenes = try await client.fetchScenes()
        XCTAssertTrue(scenes.contains { $0.id == "scene.medium" })
        try await client.activate(sceneID: "scene.medium")
    }

    func testAuthErrorAndMalformedDataDoNotExposeSecrets() async throws {
        let config = try Configuration.parse("HA_URL=https://example.com\nHA_TOKEN=secret")
        for (status, payload) in [(401, "{}"), (200, "not json")] {
            let client = HomeAssistantClient(configuration: config, transport: MockTransport(status: status, payload: payload))
            do { _ = try await client.fetchScenes(); XCTFail("Expected failure") }
            catch { XCTAssertFalse(error.localizedDescription.contains("secret")) }
        }
    }
}
