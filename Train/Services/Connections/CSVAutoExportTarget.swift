//
//  CSVAutoExportTarget.swift
//  Train
//
//  CSV auto-export (#23): keeps `train-cardio.csv` and `train-strength.csv`
//  in a folder the athlete picks (Files, iCloud Drive), rewritten on every
//  change exactly like the Sheets mirror. The folder is remembered as a
//  security-scoped bookmark. A bookmark only works on the device that made
//  it, so it lives in this device's `UserDefaults`, never in the synced
//  `AppConfiguration`.
//

import Foundation
import Observation
import SwiftData

/// Mirrors the training history as CSV files in a chosen folder.
@MainActor
@Observable
final class CSVAutoExportTarget: AutoExportTarget {

    let id: ConnectionID = .csvFile
    let capabilities: ConnectionCapabilities = [.import, .export, .autoExport]

    var status: ConnectionStatus = .disconnected

    /// The chosen folder's name, for display; `nil` when off.
    private(set) var folderName: String?

    var isConnected: Bool { folderName != nil }

    /// The files kept in the folder.
    static let cardioFileName = "train-cardio.csv"
    static let strengthFileName = "train-strength.csv"

    /// What the status says when the folder can't be reached.
    static let folderLostReason = "Can't reach the export folder"

    /// `UserDefaults` key for the folder bookmark.
    static let bookmarkKey = "connections.csvAutoExport.bookmark"

    @ObservationIgnored private let defaults: UserDefaults
    /// A folder picked but not yet connected.
    @ObservationIgnored private var pendingFolder: URL?

    /// Creates the target.
    /// - Parameter defaults: Where the bookmark is kept (this device only).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - AutoExportTarget

    /// Restores the remembered folder, if any.
    func restore(from container: ModelContainer) async {
        guard defaults.data(forKey: Self.bookmarkKey) != nil else {
            folderName = nil
            status = .disconnected
            return
        }
        if let url = resolveFolder() {
            folderName = url.lastPathComponent
            status = .connected(lastSync: nil)
        } else {
            folderName = defaults.string(forKey: Self.bookmarkKey + ".name") ?? "Folder"
            status = .needsAttention(reason: Self.folderLostReason, action: .chooseFolder)
        }
    }

    /// Picks the folder the next `connect()` will use.
    /// - Parameter url: A folder URL from the document picker.
    func choose(folder url: URL) {
        pendingFolder = url
    }

    /// Remembers the picked folder. Call through `SyncEngine.connect(_:)`
    /// so the first export runs straight away.
    func connect() async throws {
        guard let folder = pendingFolder else { throw CSVAutoExportError.noFolder }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(folder.lastPathComponent, forKey: Self.bookmarkKey + ".name")
        pendingFolder = nil
        folderName = folder.lastPathComponent
        status = .connected(lastSync: nil)
    }

    /// Forgets the folder. Files already written stay where they are.
    func disconnect() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.bookmarkKey + ".name")
        folderName = nil
        status = .disconnected
    }

    func readinessProblem() -> ConnectionStatus? {
        resolveFolder() == nil ? .needsAttention(reason: Self.folderLostReason, action: .chooseFolder) : nil
    }

    /// Rewrites both files in the folder.
    func export(_ snapshot: TrainingSnapshot) async throws {
        guard let folder = resolveFolder() else { throw CSVAutoExportError.folderUnavailable }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        for file in Self.files(for: snapshot) {
            try Data(file.text.utf8).write(to: folder.appendingPathComponent(file.name), options: .atomic)
        }
    }

    func status(afterFailure error: Error) -> ConnectionStatus {
        if case CSVAutoExportError.folderUnavailable = error {
            return .needsAttention(reason: Self.folderLostReason, action: .chooseFolder)
        }
        return .needsAttention(reason: error.localizedDescription, action: .retry)
    }

    // MARK: - Internals

    /// The two files with fixed names, so each export replaces the last.
    static func files(for snapshot: TrainingSnapshot) -> [TrainingCSVBundle.File] {
        let dated = TrainingCSVBundle.files(for: snapshot, on: Date())
        return [
            .init(name: cardioFileName, text: dated[0].text),
            .init(name: strengthFileName, text: dated[1].text)
        ]
    }

    /// The bookmarked folder, refreshing a stale bookmark; `nil` when it
    /// can't be resolved.
    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }
}

/// CSV auto-export failures.
enum CSVAutoExportError: Error, LocalizedError, Equatable {
    /// `connect()` ran before a folder was picked.
    case noFolder
    /// The bookmarked folder can't be resolved (moved, deleted, or the
    /// app lost access).
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .noFolder: return "Choose a folder first."
        case .folderUnavailable: return "The export folder can't be reached. Choose it again."
        }
    }
}
