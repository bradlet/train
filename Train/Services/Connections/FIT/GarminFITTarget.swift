//
//  GarminFITTarget.swift
//  Train
//
//  Garmin as an import source, phase 1 (#22): FIT activity files picked from
//  Files or shared into the app. No account, no approval, works offline. The
//  zero-effort alternative is Garmin Connect → Apple Health → Health import.
//

import Foundation
import UniformTypeIdentifiers

/// Reads Garmin FIT activity files into interchange records.
@MainActor
final class GarminFITTarget: ConnectionTarget {

    let id: ConnectionID = .garmin
    let capabilities: ConnectionCapabilities = [.import]

    /// The FIT file type (declared in Info.plist), falling back to raw data.
    nonisolated static let fitType = UTType("com.garmin.fit") ?? UTType(filenameExtension: "fit") ?? .data

    /// What a set of files holds.
    struct Parsed: Equatable {
        /// Workouts, oldest first.
        var records: [TrainingRecord.Cardio] = []
        /// Strength sessions left out.
        var skippedStrength = 0
        /// Files that couldn't be read, with the reason.
        var failures: [String] = []
    }

    /// Decodes and maps each file. Pure apart from the decoding.
    /// - Parameters:
    ///   - files: Each file's name and bytes.
    ///   - defaults: The athlete's inclusion and key defaults.
    nonisolated static func parse(_ files: [(name: String, data: Data)], defaults: ImportDefaults) -> Parsed {
        var parsed = Parsed()
        for file in files {
            do {
                let activity = FITActivityMapper.activity(from: try FITDecoder.messages(from: file.data), defaults: defaults)
                parsed.records += activity.records
                parsed.skippedStrength += activity.skippedStrength
                if activity.records.isEmpty && activity.skippedStrength == 0 {
                    parsed.failures.append("\(file.name) has no activity.")
                }
            } catch {
                parsed.failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
        parsed.records.sort { $0.date < $1.date }
        return parsed
    }
}
