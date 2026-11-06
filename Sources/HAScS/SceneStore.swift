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
    @ObservationIgnored private var navigationColumn: Int?
    private(set) var isActivating = false
    private(set) var isReordering = false
    @ObservationIgnored private var originalSlots: [SceneSlot]?
    @ObservationIgnored private let transport: any HTTPTransport
    private(set) var lastSentName: String?
    private(set) var activationError: String?
    private(set) var successName: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let configuration: ConfigurationRepository
    @ObservationIgnored private var client: HomeAssistantClient?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var activationGeneration = 0
    private static let assignmentKey = "sceneAssignments.v1"

    init(defaults: UserDefaults = .standard, configuration: ConfigurationRepository? = nil,
         transport: any HTTPTransport = SecureURLSessionTransport()) {
        self.defaults = defaults
        self.transport = transport
        let legacyDomain = defaults.persistentDomain(forName: IdentifierMigration.legacyBundleID)
        IdentifierMigration.migrateSceneAssignments(to: defaults, from: legacyDomain)
        self.configuration = configuration ?? ConfigurationRepository(
            defaults: defaults,
            legacyStorage: KeychainCredentialStore(service: IdentifierMigration.legacyKeychainService),
            legacyDefaults: UserDefaults(suiteName: IdentifierMigration.legacyBundleID)
        )
    }

    func refresh() async {
        guard !isReordering else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        status = .loading
        activationError = nil
        successName = nil
        do {
            let savedConfiguration = try configuration.load()
            let client = HomeAssistantClient(configuration: savedConfiguration, transport: transport)
            let scenes = try await client.fetchScenes()
            guard generation == refreshGeneration else { return }
            let previous = defaults.dictionary(forKey: Self.assignmentKey) as? [String: Int] ?? [:]
            let assigned = SceneAssignments.assign(scenes: scenes, previous: previous)
            defaults.set(Dictionary(uniqueKeysWithValues: assigned.map { ($0.id, $0.number) }), forKey: Self.assignmentKey)
            self.client = client
            self.slots = assigned
            self.totalScenes = scenes.count
            self.navigationColumn = nil
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
        guard status == .ready, !isActivating, !isReordering, let client,
              let slot = slots.first(where: { $0.number == number }), slot.scene.isAvailable else { return false }
        selectedNumber = number
        navigationColumn = nil
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
        finishReordering(save: false)
        refreshGeneration += 1
        client = nil
        slots = []
        status = .loading
        activationError = nil
        successName = nil
    }

    func resetTransientState() {
        // An in-flight HTTP request cannot be safely undone by hiding the panel.
        finishReordering(save: false)
        activationError = nil
        successName = nil
    }

    func beginReordering() {
        guard status == .ready, !isActivating, successName == nil, slots.count > 1, !isReordering else { return }
        originalSlots = slots
        isReordering = true
        activationError = nil
        if selectedNumber == nil { selectedNumber = slots.first?.number }
    }

    func finishReordering(save: Bool) {
        guard isReordering, let originalSlots else { return }
        let selectedID = slots.first(where: { $0.number == selectedNumber })?.id
        if save {
            defaults.set(Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.number) }), forKey: Self.assignmentKey)
        } else {
            slots = originalSlots
        }
        self.originalSlots = nil
        navigationColumn = nil
        isReordering = false
        selectedNumber = slots.first(where: { $0.id == selectedID && $0.scene.isAvailable })?.number
            ?? slots.first(where: { $0.scene.isAvailable })?.number
    }

    @discardableResult
    func moveScene(_ id: String, toPosition position: Int) -> Bool {
        guard isReordering, slots.contains(where: { $0.id == id }), slots.indices.contains(position) else { return false }
        slots = SceneAssignments.moving(slots, sceneID: id, toPosition: position)
        navigationColumn = nil
        selectedNumber = slots.first(where: { $0.id == id })?.number
        return true
    }

    func moveSelectedScene(_ direction: SceneGridDirection) {
        guard isReordering,
              let selected = slots.first(where: { $0.number == selectedNumber }),
              let destination = SceneGridLayout.destination(in: slots, from: selectedNumber, direction: direction,
                                                           preferredColumn: navigationColumn, includeUnavailable: true),
              let index = slots.firstIndex(where: { $0.number == destination.number }) else { return }
        if moveScene(selected.id, toPosition: index) { navigationColumn = destination.column }
    }

    func selectForReordering(_ number: Int) {
        guard isReordering, slots.contains(where: { $0.number == number }) else { return }
        navigationColumn = nil
        selectedNumber = number
    }

    func moveSelection(_ direction: SceneGridDirection) {
        guard status == .ready, !isActivating,
              let destination = SceneGridLayout.destination(in: slots, from: selectedNumber, direction: direction,
                                                           preferredColumn: navigationColumn,
                                                           includeUnavailable: isReordering) else { return }
        selectedNumber = destination.number
        navigationColumn = destination.column
    }
}
