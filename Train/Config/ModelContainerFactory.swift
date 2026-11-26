//
//  ModelContainerFactory.swift
//  Train
//
//  Centralizes ModelContainer creation for the app, previews, and tests.
//  Configures SwiftData with CloudKit sync.
//

import CoreData
import Foundation
import SwiftData

/// Factory for creating configured ModelContainer instances.
enum ModelContainerFactory {

    /// The iCloud container the app syncs to.
    static let cloudKitContainerIdentifier = "iCloud.com.bradlet.train"

    /// Every persisted model type — the schema, and what CloudKit mirrors.
    static let modelTypes: [any PersistentModel.Type] = [
        Exercise.self,
        StrengthExercise.self,
        StrengthLift.self,
        StrengthRecord.self,
        UserLibraryExercise.self,
        UserMovementGroup.self,
        FavoriteWorkout.self,
        AppConfiguration.self,
    ]

    /// The full schema used by the app.
    private static var schema: Schema {
        Schema(modelTypes)
    }

    /// Launch argument that makes a Debug build push the complete schema to
    /// CloudKit's *development* environment before opening the store (#30).
    static let initializeSchemaArgument = "-initializeCloudKitSchema"

    /// Whether the on-disk container mirrors to CloudKit.
    ///
    /// Debug builds only, for now: they use CloudKit's *development*
    /// environment. The *production* schema is not deployed yet — deploying
    /// it makes the schema additive-only for good, and the backlog still
    /// plans renames (#17) and model redesigns (#20, #24) — so Release and
    /// TestFlight builds stay local-only rather than syncing against a
    /// schema that doesn't exist. #30 deploys it and flips this to `true`.
    static let isCloudKitSyncEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Creates the app's on-disk ModelContainer, mirrored to CloudKit when
    /// `isCloudKitSyncEnabled`.
    /// - Returns: A configured ModelContainer.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: isCloudKitSyncEnabled ? .automatic : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// Creates an in-memory ModelContainer for SwiftUI previews, unit tests and
    /// `-uiTestSeed` UI tests.
    ///
    /// CloudKit is explicitly off: the app target carries an iCloud entitlement,
    /// and a configuration left at the default `.automatic` would try to mirror
    /// throwaway fixture data to the athlete's private database.
    /// - Returns: An in-memory ModelContainer with no persistence and no sync.
    static func makePreviewContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }

    #if DEBUG
    /// Creates every record type and field of the schema in CloudKit's
    /// development environment, ready for Deploy Schema Changes to
    /// production.
    ///
    /// Creating one of each record by hand is not enough: CloudKit only adds
    /// a field when a saved record carries a value for it, so optional
    /// properties that happen to be `nil` (`StrengthRecord.slotID`, …) would
    /// be missing from production, and later syncs of those fields would
    /// fail. `initializeCloudKitSchema()` uploads a representative record
    /// with every field populated, then deletes it. It runs against a
    /// throwaway store so the athlete's real store is untouched. Debug-only:
    /// Debug builds talk to the development environment.
    static func initializeCloudKitDevelopmentSchema() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            throw CocoaError(.featureUnsupported)
        }
        let storeURL = URL.temporaryDirectory.appending(path: "CloudKitSchemaInit.store")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "Train", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema()

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: storeURL)
    }
    #endif
}
