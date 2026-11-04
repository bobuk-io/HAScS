import Foundation
import Observation
import HAScSCore

@MainActor @Observable
final class SceneStore {
    enum Status: Equatable {
        case loading
        case ready
        case error(String)
    }
    private(set) var status: Status = .loading
    private(set) var slots: [SceneSlot] = []
    private(set) var totalScenes = 0
    private(set) var selectedNumber: Int?
    private(set) var isActivating = false
    private(set) var lastSentName: String?
    private(set) var activationError: String?
    private(set) var successName: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let configuration: ConfigurationRepository
    @ObservationIgnored private var client: HomeAssistantClient?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var activationGeneration = 0
    private static let assignmentKey = "sceneAssignments.v1"

    init(defaults: UserDefaults = .standard, configuration: ConfigurationRepository? = nil) {
        self.defaults = defaults
        let legacyDomain = defaults.persistentDomain(forName: IdentifierMigration.legacyBundleID)
        IdentifierMigration.migrateSceneAssignments(to: defaults, from: legacyDomain)
        self.configuration = configuration ?? ConfigurationRepository(
            defaults: defaults,
            legacyStorage: KeychainCredentialStore(service: IdentifierMigration.legacyKeychainService),
            legacyDefaults: UserDefaults(suiteName: IdentifierMigration.legacyBundleID)
        )
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        status = .loading
        activationError = nil
        successName = nil
        do {
            let savedConfiguration = try configuration.load()
            let client = HomeAssistantClient(configuration: savedConfiguration)
            let scenes = try await client.fetchScenes()
            guard generation == refreshGeneration else { return }
            let previous = defaults.dictionary(forKey: Self.assignmentKey) as? [String: Int] ?? [:]
            let assigned = SceneAssignments.assign(scenes: scenes, previous: previous)
            defaults.set(Dictionary(uniqueKeysWithValues: assigned.map { ($0.id, $0.number) }), forKey: Self.assignmentKey)
            self.client = client
            self.slots = assigned
            self.totalScenes = scenes.count
            self.selectedNumber = assigned.first(where: { $0.scene.isAvailable })?.number
            self.status = .ready
        } catch {
            guard generation == refreshGeneration else { return }
            client = nil
            slots = []
            status = .error(error.localizedDescription)
        }
    }

    func activate(number: Int) async -> Bool {
        guard status == .ready, !isActivating, let client,
              let slot = slots.first(where: { $0.number == number }), slot.scene.isAvailable else { return false }
        selectedNumber = number
        isActivating = true
        activationError = nil
        successName = nil
        activationGeneration += 1
        let generation = activationGeneration
        do {
            try await client.activate(sceneID: slot.id)
            guard generation == activationGeneration else { return false }
            isActivating = false
            lastSentName = slot.scene.name
            successName = slot.scene.name
            return true
        } catch {
            guard generation == activationGeneration else { return false }
            isActivating = false
            // An interrupted request may already have reached HA; never promise it did not.
            activationError = L10n.uncertainActivation(error.localizedDescription)
            return false
        }
    }

    func invalidateConfiguration() {
        refreshGeneration += 1
        client = nil
        slots = []
        status = .loading
        activationError = nil
        successName = nil
    }

    func resetTransientState() {
        // An in-flight HTTP request cannot be safely undone by hiding the panel.
        activationError = nil
        successName = nil
    }

    func moveSelection(_ direction: Int) {
        guard status == .ready, !isActivating else { return }
        let numbers = slots.filter { $0.scene.isAvailable }.map(\.number)
        guard !numbers.isEmpty else { return }
        let current = selectedNumber.flatMap { numbers.firstIndex(of: $0) } ?? 0
        selectedNumber = numbers[(current + direction + numbers.count) % numbers.count]
    }
}
