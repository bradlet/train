//
//  ModelContainerFactory.swift
//  Train
//
//  Centralizes ModelContainer creation for the app, previews, and tests.
//  Configures SwiftData with CloudKit sync.
//

import Foundation
import SwiftData

/// Factory for creating configured ModelContainer instances.
enum ModelContainerFactory {

    /// The full schema used by the app.
    private static var schema: Schema {
        Schema([Exercise.self, StrengthExercise.self, StrengthLift.self, StrengthRecord.self, UserLibraryExercise.self, FavoriteWorkout.self, AppConfiguration.self])
    }

    /// Creates the production ModelContainer with CloudKit sync enabled.
    /// - Returns: A configured ModelContainer.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
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
}
