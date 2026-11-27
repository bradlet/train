//
//  AppleHealthTarget.swift
//  Train
//
//  Apple Health as an `ImportSourceTarget` (#21). Import stays a manual
//  action the athlete starts ("Import now"); it never runs in the background.
//  Records come back as interchange records keyed by HealthKit UUID, and the
//  picker marks those already in the app instead of offering them again.
//

import Foundation

/// Imports recent Apple Health workouts.
@MainActor
final class AppleHealthTarget: ImportSourceTarget {

    let id: ConnectionID = .appleHealth
    let capabilities: ConnectionCapabilities = [.import]

    /// Upper bound on workouts fetched in one go.
    static let fetchLimit = 60

    private let service: HealthKitImportService

    /// Creates the target.
    /// - Parameter service: The HealthKit fetch layer (live or stub).
    init(service: HealthKitImportService) {
        self.service = service
    }

    /// Requests read access, then fetches workouts since `since`.
    func fetchImports(since: Date, defaults: ImportDefaults) async throws -> [TrainingRecord] {
        try await service.requestAuthorization()
        let workouts = try await service.fetchRecentWorkouts(since: since, limit: Self.fetchLimit)
        return workouts.map {
            .cardio(HealthKitWorkoutMapper.toRecord(
                $0,
                excludedTypes: defaults.trainingExcludedTypes,
                keyTypes: defaults.keyWorkoutTypes
            ))
        }
    }
}
