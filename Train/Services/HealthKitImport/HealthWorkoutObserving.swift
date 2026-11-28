//
//  HealthWorkoutObserving.swift
//  Train
//
//  The HealthKit side of new-workout notifications (#37): an observer query
//  with background delivery, so iOS wakes Train when any app (Apple Watch,
//  Garmin Connect, …) saves a workout to Health, and an anchored fetch that
//  returns only what's new since the last look. `HealthWorkoutWatcher`
//  decides what to do with it; `StubHealthWorkoutObserver` drives tests.
//

import Foundation
import HealthKit

/// Watches Apple Health for newly saved workouts.
protocol HealthWorkoutObserving: Sendable {
    /// Whether Train has already asked for Health access (the athlete
    /// "connected" Apple Health). Watching never prompts for it.
    func hasRequestedAuthorization() async -> Bool

    /// Bundle IDs of every app that has saved a workout to Health, used to
    /// tell whether Garmin Connect is connected.
    func workoutSourceBundleIDs() async throws -> Set<String>

    /// Starts an observer query with background delivery. `onChange` runs
    /// each time workouts change, including when iOS relaunches Train in
    /// the background; the query's completion fires after it returns.
    /// - Parameter onChange: Called on every change.
    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws

    /// Stops the observer query and background delivery.
    func stopObserving() async

    /// Workouts added since `anchor`.
    /// - Parameter anchor: The anchor a previous fetch returned, or `nil`
    ///   for everything (the caller treats that as a baseline).
    /// - Returns: The new workouts and the anchor to store for next time.
    func fetchWorkouts(after anchor: Data?) async throws -> (workouts: [HealthKitWorkout], anchor: Data?)
}

// MARK: - Live

extension LiveHealthKitImportService: HealthWorkoutObserving {

    func hasRequestedAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [HKObjectType.workoutType()])
        return status == .unnecessary
    }

    func workoutSourceBundleIDs() async throws -> Set<String> {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: HKObjectType.workoutType(), samplePredicate: nil) { _, sources, error in
                if let error {
                    continuation.resume(throwing: HealthKitImportError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: Set((sources ?? []).map(\.bundleIdentifier)))
            }
            store.execute(query)
        }
    }

    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {
        await stopObserving()
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            Task {
                await onChange()
                completion()
            }
        }
        observer.set(query)
        store.execute(query)
        try await store.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate)
    }

    func stopObserving() async {
        if let query = observer.take() {
            store.stop(query)
        }
        try? await store.disableBackgroundDelivery(for: HKObjectType.workoutType())
    }

    func fetchWorkouts(after anchor: Data?) async throws -> (workouts: [HealthKitWorkout], anchor: Data?) {
        let start = anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: nil,
                anchor: start,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: HealthKitImportError.queryFailed(underlying: error))
                    return
                }
                let workouts = (samples as? [HKWorkout] ?? []).map(Self.dto)
                let data = newAnchor.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
                continuation.resume(returning: (workouts, data))
            }
            store.execute(query)
        }
    }
}

/// The running observer query, guarded so start and stop can race safely.
final class HealthObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var query: HKObserverQuery?

    /// Stores the running query.
    func set(_ query: HKObserverQuery) {
        lock.withLock { self.query = query }
    }

    /// Removes and returns the running query.
    func take() -> HKObserverQuery? {
        lock.withLock {
            defer { query = nil }
            return query
        }
    }
}

// MARK: - Stub

/// A scripted observer for tests and previews: never touches HealthKit.
actor StubHealthWorkoutObserver: HealthWorkoutObserving {
    /// Whether Health access was "requested".
    var authorized: Bool
    /// Source bundle IDs to report.
    var sourceBundleIDs: Set<String>
    /// Every workout "in Health", in the order they were added.
    private(set) var workouts: [HealthKitWorkout]
    /// Whether an observer query is running.
    private(set) var isObserving = false
    private var onChange: (@Sendable () async -> Void)?

    /// Creates a stub.
    /// - Parameters:
    ///   - authorized: Whether Health access was already requested.
    ///   - sourceBundleIDs: Apps that saved workouts.
    ///   - workouts: Workouts already in Health.
    init(authorized: Bool = true, sourceBundleIDs: Set<String> = [], workouts: [HealthKitWorkout] = []) {
        self.authorized = authorized
        self.sourceBundleIDs = sourceBundleIDs
        self.workouts = workouts
    }

    /// Adds workouts as if another app saved them, and fires the observer.
    func save(_ new: [HealthKitWorkout]) async {
        workouts += new
        for workout in new {
            if let id = workout.sourceBundleID { sourceBundleIDs.insert(id) }
        }
        await onChange?()
    }

    func hasRequestedAuthorization() async -> Bool { authorized }

    func workoutSourceBundleIDs() async throws -> Set<String> { sourceBundleIDs }

    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {
        self.onChange = onChange
        isObserving = true
    }

    func stopObserving() async {
        onChange = nil
        isObserving = false
    }

    /// The anchor is the count of workouts already returned.
    func fetchWorkouts(after anchor: Data?) async throws -> (workouts: [HealthKitWorkout], anchor: Data?) {
        let seen = anchor.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let new = Array(workouts.dropFirst(seen))
        return (new, Data(String(workouts.count).utf8))
    }
}
