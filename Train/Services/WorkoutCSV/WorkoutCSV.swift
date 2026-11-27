//
//  WorkoutCSV.swift
//  Train
//
//  The cardio CSV codec (#21): `TrainingRecord.Cardio` ↔ rows. Shared by CSV
//  export/import and the Google Sheets Cardio tab. Pure; no SwiftData or
//  SwiftUI, so it is fully unit-testable.
//
//  Import reads columns by header name, so a missing column takes its
//  default and an unknown one is ignored. A header without a `date` column
//  falls back to the legacy fixed order (`headerColumns`' order).
//

import Foundation

/// Distance unit for the single `distance` column in the CSV schema.
/// The unit is not embedded in the column name or header; callers must
/// supply it when encoding and decoding.
enum WorkoutCSVDistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    /// Human-readable label for UI.
    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .kilometers: return "Kilometers"
        }
    }

    /// Converts a value expressed in this unit to miles (internal storage).
    func toMiles(_ value: Double) -> Double {
        switch self {
        case .miles: return value
        case .kilometers: return value / 1.60934
        }
    }

    /// Converts miles to a value expressed in this unit.
    func fromMiles(_ miles: Double) -> Double {
        switch self {
        case .miles: return miles
        case .kilometers: return miles * 1.60934
        }
    }
}

/// A single parsed CSV row before being materialized into a `Workout`.
struct WorkoutCSVRow: Equatable {
    var date: Date
    var name: String
    var type: ExerciseType
    var durationSeconds: Int
    /// Distance expressed in the unit chosen by the caller of `parse`/`encode`.
    var distance: Double
    var notes: String
    /// Subjective 1-5 feeling; `nil` when the column is blank.
    var feeling: Int?
    /// Subjective 1-10 perceived exertion; `nil` when the column is blank.
    var perceivedExertion: Int?
    /// Whether the workout counts toward training (#29); `true` when the
    /// column is missing or blank, so older files import as before.
    var countsTowardTraining: Bool = true
    /// Whether the athlete marked it key (#25); `false` when missing.
    var isKeyWorkout: Bool = false
    /// Provenance (`WorkoutSource` raw value); `nil` when the column is
    /// missing or blank, which imports as CSV.
    var source: String? = nil
    /// Dedupe anchor (#21); `nil` when missing or blank.
    var id: String? = nil
}

/// Errors raised only for whole-file failures. Per-row problems are
/// collected into `ParseResult.skipped` instead of throwing.
enum WorkoutCSVError: Error, Equatable {
    case empty
    case missingHeader
}

/// Result of parsing a CSV document.
struct WorkoutCSVParseResult: Equatable {
    /// Successfully parsed rows, in source order.
    var rows: [WorkoutCSVRow]
    /// Lines that failed validation, paired with a short human-readable reason.
    /// Line numbers are 1-based and refer to the row's starting line in the
    /// source text (header row is line 1).
    var skipped: [SkippedRow]

    struct SkippedRow: Equatable {
        var line: Int
        var reason: String
    }
}

/// Stateless CSV codec for `Workout` history.
enum WorkoutCSV {

    /// Column names, in export order. Import finds them by name; a header
    /// without `date` is read positionally in this order (legacy files).
    static let headerColumns = [
        "date", "name", "type", "duration", "distance", "notes",
        "feeling", "perceived_exertion", "counts_toward_training", "key_workout",
        "source", "id"
    ]

    /// CSV header line (joined `headerColumns`).
    static let header = headerColumns.joined(separator: ",")

    // MARK: - Encoding

    /// Encodes cardio records as a 2D matrix, header first, oldest first.
    /// Distance is converted from internal miles to `unit`. Used by both CSV
    /// export (after escape + join) and the Sheets Cardio tab (raw rows).
    static func rows(cardio: [TrainingRecord.Cardio], unit: WorkoutCSVDistanceUnit) -> [[String]] {
        [headerColumns] + cardio.sorted { $0.date < $1.date }.map { rowColumns($0, unit: unit) }
    }

    /// Encodes recorded exercises (planned-only ones are skipped) as a 2D
    /// matrix, header first, oldest first.
    static func rows(exercises: [Exercise], unit: WorkoutCSVDistanceUnit) -> [[String]] {
        rows(cardio: exercises.compactMap(TrainingRecord.Cardio.init(exercise:)), unit: unit)
    }

    /// Encodes recorded exercises to a CSV document ending with a newline.
    static func encode(exercises: [Exercise], unit: WorkoutCSVDistanceUnit) -> String {
        CSVTable.document(rows(exercises: exercises, unit: unit))
    }

    /// Encodes cardio records to a CSV document ending with a newline.
    static func encode(cardio: [TrainingRecord.Cardio], unit: WorkoutCSVDistanceUnit) -> String {
        CSVTable.document(rows(cardio: cardio, unit: unit))
    }

    /// Serializes a single recorded exercise as one CSV row (no trailing
    /// newline). Returns `""` for a planned exercise that was never recorded.
    static func encodeRow(exercise: Exercise, unit: WorkoutCSVDistanceUnit) -> String {
        guard let record = TrainingRecord.Cardio(exercise: exercise) else { return "" }
        return rowColumns(record, unit: unit).map(CSVTable.escape).joined(separator: ",")
    }

    /// Raw column values for one record, in `headerColumns` order.
    private static func rowColumns(_ record: TrainingRecord.Cardio, unit: WorkoutCSVDistanceUnit) -> [String] {
        [
            mdyyyyFormatter.string(from: record.date),
            record.name,
            record.type.rawValue,
            formatDuration(record.durationSeconds),
            formatDistance(unit.fromMiles(record.distanceMiles)),
            record.notes,
            record.feeling.map(String.init) ?? "",
            record.perceivedExertion.map(String.init) ?? "",
            record.countsTowardTraining ? "true" : "false",
            record.isKeyWorkout ? "true" : "false",
            record.source,
            record.externalID ?? ""
        ]
    }

    // MARK: - Decoding

    /// Parses a CSV document into rows. The first line is the header: its
    /// names locate the columns, or, without a `date` column, the rows are
    /// read in the legacy fixed order.
    /// - Parameter csv: Full CSV document text.
    /// - Throws: `WorkoutCSVError.empty` if the document is empty or whitespace only.
    ///           `WorkoutCSVError.missingHeader` if no header line can be found.
    /// - Returns: A `WorkoutCSVParseResult` with successful rows and skipped rows.
    static func parse(_ csv: String) throws -> WorkoutCSVParseResult {
        let trimmed = csv.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkoutCSVError.empty }

        let records = CSVTable.tokenize(csv)
        guard let headerRecord = records.first else { throw WorkoutCSVError.missingHeader }
        let header = CSVTable.Header(headerRecord.fields)
        let layout: Layout = header.contains("date") ? .named(header) : .legacy
        let dataRecords = records.dropFirst()

        var rows: [WorkoutCSVRow] = []
        var skipped: [WorkoutCSVParseResult.SkippedRow] = []

        for record in dataRecords {
            // Skip fully blank lines silently.
            if record.isBlank { continue }

            let outcome = decodeRow(record.fields, layout: layout)
            switch outcome {
            case .row(let row):
                rows.append(row)
            case .skip(let reason):
                skipped.append(.init(line: record.startLine, reason: reason))
            }
        }

        return WorkoutCSVParseResult(rows: rows, skipped: skipped)
    }

    /// Converts a parsed row to the interchange record, applying the
    /// distance unit to get internal miles. A row without a source imports
    /// as CSV; its `id` becomes the record's dedupe anchor.
    static func toRecord(_ row: WorkoutCSVRow, unit: WorkoutCSVDistanceUnit) -> TrainingRecord.Cardio {
        TrainingRecord.Cardio(
            externalID: row.id,
            source: row.source ?? WorkoutSource.csv.rawValue,
            date: row.date,
            name: row.name,
            type: row.type,
            durationSeconds: row.durationSeconds,
            distanceMiles: unit.toMiles(row.distance),
            notes: row.notes,
            feeling: row.feeling,
            perceivedExertion: row.perceivedExertion,
            countsTowardTraining: row.countsTowardTraining,
            isKeyWorkout: row.isKeyWorkout
        )
    }

    /// Converts a parsed CSV row into a single completed `Exercise` whose
    /// planned targets and recorded actuals both carry the row's metrics.
    static func toExercise(_ row: WorkoutCSVRow, unit: WorkoutCSVDistanceUnit) -> Exercise {
        toRecord(row, unit: unit).makeExercise()
    }

    // MARK: - Duration Parsing

    /// Parses a flexible duration string into total seconds.
    ///
    /// Supported formats:
    /// - Plain integer (no unit suffix): treated as seconds (e.g., `"1800"` → 1800)
    /// - Unit-tagged components: `_h`, `_m`, `_s` in any order, separated by
    ///   optional whitespace. Decimal values are floored. All units are optional.
    ///   Examples: `"40m"` → 2400, `"2h 30m"` → 9000, `"1h 30m 45s"` → 5445
    ///
    /// Returns `nil` for empty or unparseable input.
    static func parseDuration(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Plain integer with no unit suffix → seconds.
        if let seconds = Int(trimmed) {
            return seconds >= 0 ? seconds : nil
        }

        // Scan for unit-tagged components: number followed by h/m/s.
        var total = 0
        var foundAny = false
        var remaining = trimmed[...]

        while !remaining.isEmpty {
            // Skip whitespace between components.
            remaining = remaining.drop(while: { $0.isWhitespace })
            if remaining.isEmpty { break }

            // Extract the numeric part (digits and optional decimal point).
            let numStart = remaining.startIndex
            let numPart = remaining.prefix(while: { $0.isNumber || $0 == "." })
            guard !numPart.isEmpty else { return nil }

            guard let value = Double(numPart) else { return nil }
            remaining = remaining[numPart.endIndex...]

            // Extract the unit suffix.
            guard let unit = remaining.first else { return nil }
            let lowered = unit.lowercased()
            let multiplier: Int
            switch lowered {
            case "h": multiplier = 3600
            case "m": multiplier = 60
            case "s": multiplier = 1
            default: return nil
            }
            remaining = remaining[remaining.index(after: remaining.startIndex)...]

            total += Int(value) * multiplier
            foundAny = true
        }

        return foundAny ? total : nil
    }

    /// Formats a duration in seconds to a human-readable string (e.g., `"1h 30m"`).
    static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    // MARK: - Internals

    /// ISO8601 formatter with internet date-time format.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Fallback ISO8601 formatter that also accepts fractional seconds, since
    /// some exports (and many CSV editors) produce them.
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// DateFormatter for `yyyy-MM-dd` format. Uses the user's local timezone
    /// so plain dates without timezone info land on the correct calendar day.
    private static let yyyyMMddFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// DateFormatter for `M/d/yyyy` format (handles single- and double-digit month/day).
    /// Uses the user's local timezone so plain dates land on the correct calendar day.
    static let mdyyyyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Formats distance with fixed 2-decimal precision using the POSIX locale
    /// so the decimal separator is always a period.
    private static func formatDistance(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Outcome of decoding a single tokenized row.
    private enum DecodeOutcome {
        case row(WorkoutCSVRow)
        case skip(String)
    }

    /// Where a row's columns are: by header name, or the legacy fixed order.
    private enum Layout {
        case named(CSVTable.Header)
        case legacy

        /// A field's raw text, `nil` when the column is absent.
        /// - Parameters:
        ///   - names: The column's name, then any legacy aliases.
        ///   - fields: The row's fields.
        func value(_ names: [String], in fields: [String]) -> String? {
            switch self {
            case .named(let header):
                return header.value(names, in: fields)
            case .legacy:
                guard let index = WorkoutCSV.headerColumns.firstIndex(of: names[0]) else { return nil }
                return index < fields.count ? fields[index] : nil
            }
        }
    }

    /// Decodes a tokenized row's fields into a `WorkoutCSVRow`.
    /// Returns `.skip` with a short human-readable reason on failure.
    /// A legacy row needs at least 5 fields (date, name, type, duration,
    /// distance); a named row needs a date, and a missing duration or
    /// distance column reads as 0. Notes default to "", both ratings to
    /// `nil`, counts-toward-training to `true` and key to `false`.
    private static func decodeRow(_ fields: [String], layout: Layout) -> DecodeOutcome {
        if case .legacy = layout, fields.count < 5 {
            return .skip("expected at least 5 fields, got \(fields.count)")
        }

        let dateString = layout.value(["date"], in: fields) ?? ""
        let name = layout.value(["name"], in: fields) ?? ""
        let typeString = layout.value(["type"], in: fields) ?? ""
        let durationString = layout.value(["duration", "duration_seconds"], in: fields) ?? "0"
        let distanceString = layout.value(["distance"], in: fields) ?? "0"
        let notes = layout.value(["notes"], in: fields) ?? ""
        let feelingString = layout.value(["feeling", "felt_rating"], in: fields) ?? ""
        let exertionString = layout.value(["perceived_exertion", "rpe"], in: fields) ?? ""
        let countsString = layout.value(["counts_toward_training", "counts_toward_mileage"], in: fields) ?? ""
        let keyString = layout.value(["key_workout"], in: fields)
        let source = CSVTable.nonEmpty(layout.value(["source"], in: fields))
        let id = CSVTable.nonEmpty(layout.value(["id"], in: fields))

        guard let date = parseDate(dateString) else {
            return .skip("invalid date '\(dateString)'")
        }
        guard let duration = parseDuration(durationString) else {
            return .skip("invalid duration '\(durationString)'")
        }
        guard let distance = Double(distanceString.trimmingCharacters(in: .whitespaces)) else {
            return .skip("invalid distance '\(distanceString)'")
        }

        let feeling: Int?
        switch parseRating(feelingString, into: 1...5, column: "feeling") {
        case .value(let value): feeling = value
        case .invalid(let reason): return .skip(reason)
        }
        let exertion: Int?
        switch parseRating(exertionString, into: 1...10, column: "perceived_exertion") {
        case .value(let value): exertion = value
        case .invalid(let reason): return .skip(reason)
        }

        let type = ExerciseType.fromCSV(typeString) ?? ExerciseType(rawValue: typeString) ?? .other

        // Infer name from exercise type display name if blank.
        let resolvedName = name.trimmingCharacters(in: .whitespaces).isEmpty ? type.rawValue : name

        return .row(WorkoutCSVRow(
            date: date,
            name: resolvedName,
            type: type,
            durationSeconds: duration,
            distance: distance,
            notes: notes,
            feeling: feeling,
            perceivedExertion: exertion,
            countsTowardTraining: parseCounts(countsString),
            isKeyWorkout: CSVTable.bool(keyString, default: false),
            source: source,
            id: id
        ))
    }

    /// Parses the counts-toward-training column leniently: "false", "no"
    /// and "0" (any case) mean excluded; anything else — including blank or
    /// a missing column — counts, so older files import unchanged.
    static func parseCounts(_ raw: String) -> Bool {
        !["false", "no", "0"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Parses an optional rating column.
    ///
    /// Blank and `"0"` both mean "not recorded" — `0` was the sentinel the
    /// legacy `felt_rating` column used, so old exports re-import cleanly.
    /// Out-of-range numbers are clamped rather than rejected, matching the
    /// importer's lenient posture elsewhere (unknown types become `.other`)
    /// and keeping a re-import of an old 1–10 `felt_rating` column from
    /// skipping most of its rows.
    /// - Parameters:
    ///   - raw: The raw column text.
    ///   - bounds: Valid range for this rating.
    ///   - column: Column name, used in the skip reason.
    /// - Returns: `.value` with the clamped rating (or `nil` when unrecorded),
    ///   or `.invalid` carrying a human-readable reason when the text is not
    ///   a number.
    private static func parseRating(
        _ raw: String,
        into bounds: ClosedRange<Int>,
        column: String
    ) -> RatingParse {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .value(nil) }
        guard let parsed = Int(trimmed) else {
            return .invalid("invalid \(column) '\(raw)'")
        }
        guard parsed != 0 else { return .value(nil) }
        return .value(min(max(parsed, bounds.lowerBound), bounds.upperBound))
    }

    /// Outcome of parsing one optional rating column.
    private enum RatingParse {
        case value(Int?)
        case invalid(String)
    }

    /// UTC calendar used to extract date components from ISO8601 dates.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Parses a date string, trying multiple formats in order:
    /// ISO8601, ISO8601 with fractional seconds, yyyy-MM-dd, M/d/yyyy.
    ///
    /// All results are normalized to the start of the calendar day in the
    /// user's local timezone. CSV dates represent calendar days, so
    /// `2025-08-04T00:00:00Z` should land on August 4th regardless of the
    /// user's timezone offset from UTC.
    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // ISO8601 dates include timezone info (the Z suffix), so we must
        // extract year/month/day in UTC to get the intended calendar date,
        // then rebuild at local midnight.
        if let d = iso8601Formatter.date(from: trimmed) { return localMidnight(fromUTC: d) }
        if let d = iso8601FractionalFormatter.date(from: trimmed) { return localMidnight(fromUTC: d) }

        // Plain date formats use the local timezone (no TZ in the string),
        // so startOfDay in local time is correct.
        if let d = yyyyMMddFormatter.date(from: trimmed) { return Calendar.current.startOfDay(for: d) }
        if let d = mdyyyyFormatter.date(from: trimmed) { return Calendar.current.startOfDay(for: d) }
        return nil
    }

    /// Extracts year/month/day from a UTC date and returns local midnight
    /// for that calendar date. This ensures `2025-08-04T00:00:00Z` becomes
    /// August 4th at midnight local time, not August 3rd.
    private static func localMidnight(fromUTC date: Date) -> Date {
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: comps) ?? date
    }
}
