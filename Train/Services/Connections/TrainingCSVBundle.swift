//
//  TrainingCSVBundle.swift
//  Train
//
//  Manual CSV export and import as a pair of files (#21): cardio and
//  strength, written together into one folder and read back in any
//  combination. Each file's kind comes from its header. `TrainingExportDocument`
//  hands the folder to `.fileExporter`.
//

import SwiftUI
import UniformTypeIdentifiers

/// The files a manual export writes, and the parse of files picked to import.
enum TrainingCSVBundle {

    /// One CSV file: its name and text.
    struct File: Equatable {
        var name: String
        var text: String
    }

    /// The export folder's name, e.g. `train-export-2026-11-27`.
    static func folderName(on date: Date) -> String {
        "train-export-\(dayFormatter.string(from: date))"
    }

    /// The export: `train-cardio-<date>.csv` and `train-strength-<date>.csv`,
    /// each with a header even when empty, so the pair always round-trips.
    /// - Parameters:
    ///   - snapshot: What to write.
    ///   - date: Stamped into the file names.
    static func files(for snapshot: TrainingSnapshot, on date: Date) -> [File] {
        let day = dayFormatter.string(from: date)
        let unit: WorkoutCSVDistanceUnit = snapshot.useMetricUnits ? .kilometers : .miles
        return [
            File(name: "train-cardio-\(day).csv", text: WorkoutCSV.encode(cardio: snapshot.cardio, unit: unit)),
            File(name: "train-strength-\(day).csv", text: StrengthCSV.encode(strength: snapshot.strength, metric: snapshot.useMetricUnits))
        ]
    }

    /// Parsed files waiting for the athlete to confirm.
    struct Parsed: Equatable {
        /// Cardio rows from every cardio file, plus their skipped rows.
        var cardio = WorkoutCSVParseResult(rows: [], skipped: [])
        /// Strength sessions from every strength file, plus skipped rows.
        var strength = StrengthCSVParseResult(records: [], skipped: [])
        /// Names of the files read.
        var fileNames: [String] = []
        /// Files that couldn't be read at all, with the reason.
        var failures: [String] = []

        /// Rows that failed validation, across both kinds.
        var skippedCount: Int { cardio.skipped.count + strength.skipped.count }
        /// Whether there is anything to import.
        var isEmpty: Bool { cardio.rows.isEmpty && strength.records.isEmpty }

        /// Every parsed row as interchange records; cardio distance is read
        /// in `unit` (the cardio file names no unit, strength rows do).
        /// - Parameter unit: The cardio distance unit the athlete confirmed.
        func records(cardioUnit unit: WorkoutCSVDistanceUnit) -> [TrainingRecord] {
            cardio.rows.map { .cardio(WorkoutCSV.toRecord($0, unit: unit)) }
                + strength.records.map(TrainingRecord.strength)
        }

        /// How many records are already in the app and will be skipped.
        /// - Parameter known: Anchors already present (`TrainingImporter.knownIDs`).
        func duplicateCount(known: Set<String>) -> Int {
            records(cardioUnit: .miles).filter { !TrainingImporter.isNew($0, known: known) }.count
        }
    }

    /// Parses picked files, detecting each one's kind from its header.
    /// - Parameter files: The files' names and texts.
    static func parse(_ files: [File]) -> Parsed {
        var parsed = Parsed()
        for file in files {
            parsed.fileNames.append(file.name)
            do {
                switch TrainingCSVKind.detect(file.text) {
                case .strength:
                    let result = try StrengthCSV.parse(file.text)
                    parsed.strength.records += result.records
                    parsed.strength.skipped += result.skipped
                case .cardio:
                    let result = try WorkoutCSV.parse(file.text)
                    parsed.cardio.rows += result.rows
                    parsed.cardio.skipped += result.skipped
                case nil:
                    parsed.failures.append("\(file.name) is empty.")
                }
            } catch WorkoutCSVError.empty {
                parsed.failures.append("\(file.name) is empty.")
            } catch WorkoutCSVError.missingHeader {
                parsed.failures.append("\(file.name) is missing a header row.")
            } catch {
                parsed.failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
        return parsed
    }

    /// `yyyy-MM-dd`, POSIX, for file names.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// A folder holding the export's CSV files, for `.fileExporter`.
struct TrainingExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    /// The files to write into the folder.
    var files: [TrainingCSVBundle.File]

    /// Creates the document for export.
    init(files: [TrainingCSVBundle.File]) {
        self.files = files
    }

    /// Reads a folder of CSV files. Not used by the app (import goes through
    /// `.fileImporter`) but required by `FileDocument`.
    init(configuration: ReadConfiguration) throws {
        files = (configuration.file.fileWrappers ?? [:]).compactMap { name, wrapper in
            guard let data = wrapper.regularFileContents, let text = String(data: data, encoding: .utf8) else { return nil }
            return TrainingCSVBundle.File(name: name, text: text)
        }
    }

    /// One UTF-8 file per CSV, inside a directory wrapper.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var children: [String: FileWrapper] = [:]
        for file in files {
            let wrapper = FileWrapper(regularFileWithContents: Data(file.text.utf8))
            wrapper.preferredFilename = file.name
            children[file.name] = wrapper
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}
