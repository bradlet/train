//
//  LiveHealthKitImportService.swift
//  Train
//
//  Production `HealthKitImportService` backed by a real `HKHealthStore`.
//  Requests read-only access for `HKObjectType.workoutType()` and runs an
//  `HKSampleQuery` for the requested time window, converting each result
//  into a source-agnostic `HealthKitWorkout` DTO before crossing isolation
//  boundaries.
//

import Foundation
import HealthKit

/// Live HealthKit-backed implementation of `HealthKitImportService`.
///
/// Holds a single shared `HKHealthStore` instance for the lifetime of the
/// app. Marked `@unchecked Sendable` because `HKHealthStore` is a reference
/// type we never mutate after construction; this mirrors the pattern used
/// by `MLXAICoachService`.
final class LiveHealthKitImportService: HealthKitImportService, @unchecked Sendable {

    let store = HKHealthStore()
    /// The new-workout observer query, when watching (#37).
    let observer = HealthObserverBox()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitImportError.healthDataUnavailable
        }
        do {
            try await store.requestAuthorization(
                toShare: [],
                read: [HKObjectType.workoutType()]
            )
        } catch {
            throw HealthKitImportError.authorizationFailed(underlying: error)
        }
    }

    func fetchRecentWorkouts(since: Date, limit: Int) async throws -> [HealthKitWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: since,
            end: nil,
            options: .strictStartDate
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )
        let workoutType = HKObjectType.workoutType()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(
                        throwing: HealthKitImportError.queryFailed(underlying: error)
                    )
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let dtos = workouts.map(Self.dto)
                continuation.resume(returning: dtos)
            }
            self.store.execute(query)
        }
    }

    /// The DTO for a HealthKit workout, including the app that saved it.
    static func dto(_ workout: HKWorkout) -> HealthKitWorkout {
        HealthKitWorkout(
            id: workout.uuid.uuidString,
            activityType: workout.workoutActivityType,
            startDate: workout.startDate,
            duration: workout.duration,
            distanceMiles: workout.totalDistance?.doubleValue(for: .mile()),
            sourceBundleID: workout.sourceRevision.source.bundleIdentifier
        )
    }
}
