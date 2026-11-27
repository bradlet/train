//
//  SyncEngine.swift
//  Train
//
//  Keeps every `AutoExportTarget` current (#21), generalising what the Google
//  Sheets coordinator used to do alone: debounce changes, read one
//  `TrainingSnapshot`, export it to each connected target, and keep each
//  target's status honest (syncing → connected, or needs attention).
//
//  Changes are picked up from `ModelContext.didSave` for the training models,
//  so every save path (cardio, strength, imports, the coach) syncs without
//  a hook at the call site.
//
//  The `syncNow()` / `performSync()` split is load-bearing: the debounce task
//  calls `performSync()` directly. Routing it through `syncNow()` would
//  `.cancel()` the task on itself mid-upload and surface as a
//  `CancellationError`. `StubGoogleSheetsAPI` checks for that regression.
//

import Foundation
import Observation
import SwiftData

/// Debounces training changes and exports them to every connected target.
@MainActor
@Observable
final class SyncEngine {

    /// The auto-export targets, in display order.
    let targets: [any AutoExportTarget]
    /// Seconds after the last change before exporting. Tunable in tests.
    let debounceSeconds: UInt64

    @ObservationIgnored private weak var modelContainer: ModelContainer?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    /// The models whose saves change what an export writes.
    static let trainingEntityNames: Set<String> = ["Exercise", "StrengthRecord", "StrengthLift"]

    /// Creates an engine.
    /// - Parameters:
    ///   - targets: The auto-export targets it keeps current.
    ///   - debounceSeconds: Quiet period before an export.
    init(targets: [any AutoExportTarget], debounceSeconds: UInt64 = 10) {
        self.targets = targets
        self.debounceSeconds = debounceSeconds
    }

    /// Whether any target is set up.
    var hasConnectedTarget: Bool { targets.contains { $0.isConnected } }

    // MARK: - Lifecycle

    /// Wires the engine to the store, restores each target, and starts
    /// watching saves. Call once at launch.
    /// - Parameters:
    ///   - modelContainer: The app's container.
    ///   - observesSaves: Whether to sync on `ModelContext.didSave`. Tests
    ///     that drive the engine by hand turn it off.
    func attach(modelContainer: ModelContainer, observesSaves: Bool = true) async {
        self.modelContainer = modelContainer
        for target in targets {
            await target.restore(from: modelContainer)
        }
        guard observesSaves, saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] notification in
            let relevant = SyncEngine.touchesTraining(notification.userInfo)
            guard relevant else { return }
            MainActor.assumeIsolated { self?.requestSync() }
        }
    }

    /// Sets a target up, then exports to it straight away.
    /// - Parameter target: The target to connect.
    func connect(_ target: any AutoExportTarget) async throws {
        try await target.connect()
        await syncNow()
    }

    // MARK: - Syncing

    /// Schedules an export `debounceSeconds` from now; calls inside the
    /// window collapse into one. Connected targets show `.syncing` at once.
    func requestSync() {
        guard hasConnectedTarget else { return }
        debounceTask?.cancel()
        for target in targets where target.isConnected && target.readinessProblem() == nil {
            target.status = .syncing
        }
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            // Drop the reference *before* exporting: a change during the
            // upload must schedule a fresh debounce, never cancel this one.
            self.debounceTask = nil
            await self.performSync()
        }
    }

    /// Exports now, bypassing the debounce. For batch imports, retry, and
    /// right after connecting.
    func syncNow() async {
        // Only direct callers reach here; the debounce task calls
        // `performSync()` itself, so it never cancels its own upload.
        debounceTask?.cancel()
        debounceTask = nil
        await performSync()
    }

    /// The shared export path. Never touches `debounceTask`, so the
    /// debounce task can call it without cancelling itself.
    private func performSync() async {
        guard let modelContainer else { return }
        let connected = targets.filter(\.isConnected)
        guard !connected.isEmpty else { return }

        let snapshot: TrainingSnapshot
        do {
            snapshot = try TrainingSnapshot.load(from: ModelContext(modelContainer))
        } catch {
            for target in connected {
                target.status = .needsAttention(reason: error.localizedDescription, action: .retry)
            }
            return
        }

        for target in connected {
            if let problem = target.readinessProblem() {
                target.status = problem
                continue
            }
            target.status = .syncing
            do {
                try await target.export(snapshot)
                // `disconnect()` may have run during the upload; a success
                // status after turning sync off would be confusing.
                guard target.isConnected else { continue }
                target.status = .connected(lastSync: Date())
            } catch {
                guard target.isConnected else { continue }
                target.status = target.status(afterFailure: error)
            }
        }
    }

    // MARK: - Save filtering

    /// Whether a `ModelContext.didSave` payload changed a training model.
    /// Pure, so it is unit-testable without a notification.
    /// - Parameter userInfo: The notification's user info.
    nonisolated static func touchesTraining(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let userInfo else { return false }
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.contains { key in
            let ids = userInfo[key.rawValue] as? [PersistentIdentifier] ?? []
            return ids.contains { trainingEntityNames.contains($0.entityName) }
        }
    }
}
