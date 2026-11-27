//
//  ImportBatch.swift
//  Train
//
//  One entry in the import log (#21): what a single import added and from
//  where. The rows it created carry its `id` as their `importBatchID`, which
//  is how "Undo last import" removes exactly that batch. Written only by
//  `TrainingImporter`.
//

import Foundation
import SwiftData

/// A logged import: its source, when it ran and what it added.
@Model
final class ImportBatch {
    /// Stamped on every row the import created.
    var id: UUID = UUID()
    /// When the import ran.
    var date: Date = Date()
    /// Raw `ConnectionID`. Access through `source`.
    private var sourceRaw: String = ConnectionID.csvFile.rawValue
    /// Cardio workouts added.
    var cardioCount: Int = 0
    /// Strength sessions added.
    var strengthCount: Int = 0
    /// Records skipped because they were already in the app.
    var duplicateCount: Int = 0

    /// Where the import came from. Unknown raw values read as CSV.
    var source: ConnectionID {
        get { ConnectionID(rawValue: sourceRaw) ?? .csvFile }
        set { sourceRaw = newValue.rawValue }
    }

    /// Total records added.
    var addedCount: Int { cardioCount + strengthCount }

    /// Creates a log entry.
    /// - Parameters:
    ///   - source: Where the import came from.
    ///   - date: When it ran.
    ///   - cardioCount: Cardio workouts added.
    ///   - strengthCount: Strength sessions added.
    ///   - duplicateCount: Records skipped as already present.
    init(source: ConnectionID, date: Date = Date(), cardioCount: Int = 0, strengthCount: Int = 0, duplicateCount: Int = 0) {
        self.id = UUID()
        self.date = date
        self.sourceRaw = source.rawValue
        self.cardioCount = cardioCount
        self.strengthCount = strengthCount
        self.duplicateCount = duplicateCount
    }

    /// A one-line summary, e.g. "3 cardio, 12 strength from CSV".
    var summary: String {
        var parts: [String] = []
        if cardioCount > 0 { parts.append("\(cardioCount) cardio") }
        if strengthCount > 0 { parts.append("\(strengthCount) strength") }
        let what = parts.isEmpty ? "Nothing" : parts.joined(separator: ", ")
        return "\(what) from \(source.displayName)"
    }
}
