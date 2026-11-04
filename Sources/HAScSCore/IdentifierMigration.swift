import Foundation

public enum IdentifierMigration {
    public static let legacyBundleID = "com.bobuk.HAScS"
    public static let legacyKeychainService = "com.bobuk.HAScS.credentials.v1"
    private static let sceneAssignmentsKey = "sceneAssignments.v1"
    private static let assignmentsMigrationKey = "identifierMigration.sceneAssignments.v1"

    /// Copy only the non-secret scene mapping, never overwriting newer settings.
    /// Keep the original domain untouched for rollback.
    public static func migrateSceneAssignments(to defaults: UserDefaults,
                                               from legacyDomain: [String: Any]?) {
        guard !defaults.bool(forKey: assignmentsMigrationKey) else { return }
        if defaults.object(forKey: sceneAssignmentsKey) == nil,
           let assignments = legacyDomain?[sceneAssignmentsKey] as? [String: Int] {
            defaults.set(assignments, forKey: sceneAssignmentsKey)
        }
        defaults.set(true, forKey: assignmentsMigrationKey)
    }
}
