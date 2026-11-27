//
//  StrengthCSV.swift
//  Train
//
//  The strength CSV codec (#21): `TrainingRecord.Strength` ↔ rows. Shared by
//  CSV export/import (`train-strength-<date>.csv`) and the Google Sheets
//  Strength tab. One row is one recorded session of one lift, matching the
//  app's one-number-per-session model. Pure; no SwiftData.
//
//  Every row carries its own `unit`, so a file reads correctly whatever the
//  importing device's unit preference is. Columns are found by header name.
//

import Foundation

/// Which kind of training a CSV file holds, read from its header.
enum TrainingCSVKind: String, Equatable, Sendable {
    case cardio
    case strength

    /// Detects a file's kind: a `lift` column means strength, anything else
    /// is read as cardio (every cardio file ever exported, including legacy
    /// headerless-schema ones).
    /// - Parameter csv: The document text.
    /// - Returns: `nil` for an empty document.
    static func detect(_ csv: String) -> TrainingCSVKind? {
        guard let first = CSVTable.tokenize(csv).first(where: { !$0.isBlank }) else { return nil }
        return CSVTable.Header(first.fields).contains("lift") ? .strength : .cardio
    }
}

/// Result of parsing a strength CSV document.
struct StrengthCSVParseResult: Equatable {
    /// Successfully parsed sessions, in source order.
    var records: [TrainingRecord.Strength]
    /// Rows that failed validation, with 1-based line numbers.
    var skipped: [WorkoutCSVParseResult.SkippedRow]
}

/// Stateless CSV codec for strength sessions.
enum StrengthCSV {

    /// Column names, in export order.
    static let headerColumns = [
        "date", "lift", "muscle_group", "metric", "value", "unit", "measurement",
        "light", "notes", "counts_toward_training", "lift_id", "id"
    ]

    // MARK: - Encoding

    /// Encodes sessions as a 2D matrix, header first, oldest first. Weight
    /// and distance are written in the athlete's units, named per row.
    /// - Parameters:
    ///   - strength: The sessions to write.
    ///   - metric: Whether to write kg and m (else lb and yd).
    static func rows(strength: [TrainingRecord.Strength], metric: Bool) -> [[String]] {
        [headerColumns] + strength.sorted { $0.date < $1.date }.map { rowColumns($0, metric: metric) }
    }

    /// Encodes sessions to a CSV document ending with a newline.
    static func encode(strength: [TrainingRecord.Strength], metric: Bool) -> String {
        CSVTable.document(rows(strength: strength, metric: metric))
    }

    /// Raw column values for one session, in `headerColumns` order.
    private static func rowColumns(_ record: TrainingRecord.Strength, metric: Bool) -> [String] {
        [
            WorkoutCSV.mdyyyyFormatter.string(from: record.date),
            record.liftName,
            record.muscleGroup.rawValue,
            record.metric.rawValue,
            record.value.map { formatNumber(record.metric.displayValue(fromStored: $0, metric: metric)) } ?? "",
            unit(for: record.metric, metric: metric),
            record.measurement?.rawValue ?? "",
            record.isLight ? "true" : "false",
            record.notes,
            record.countsTowardTraining ? "true" : "false",
            record.liftKey,
            record.externalID ?? ""
        ]
    }

    /// The unit a value is written in.
    /// - Parameters:
    ///   - liftMetric: The record's metric.
    ///   - metric: Whether the athlete uses metric units.
    static func unit(for liftMetric: LiftMetric, metric: Bool) -> String {
        switch liftMetric {
        case .weight: return metric ? "kg" : "lb"
        case .reps: return "reps"
        case .time: return "s"
        case .distance: return metric ? "m" : "yd"
        }
    }

    /// Up to two decimals with trailing zeros dropped, POSIX separator.
    static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    // MARK: - Decoding

    /// Parses a strength CSV document. Columns are found by name; a row
    /// needs a date and a lift (name or `lift_id`).
    /// - Throws: `WorkoutCSVError.empty` for an empty document,
    ///   `.missingHeader` when the header has no `lift` column.
    static func parse(_ csv: String) throws -> StrengthCSVParseResult {
        guard !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkoutCSVError.empty }
        let records = CSVTable.tokenize(csv)
        guard let headerRecord = records.first else { throw WorkoutCSVError.missingHeader }
        let header = CSVTable.Header(headerRecord.fields)
        guard header.contains("lift") || header.contains("lift_id") else { throw WorkoutCSVError.missingHeader }

        var parsed: [TrainingRecord.Strength] = []
        var skipped: [WorkoutCSVParseResult.SkippedRow] = []
        for record in records.dropFirst() where !record.isBlank {
            switch decodeRow(record.fields, header: header) {
            case .success(let row): parsed.append(row)
            case .failure(let failure): skipped.append(.init(line: record.startLine, reason: failure.reason))
            }
        }
        return StrengthCSVParseResult(records: parsed, skipped: skipped)
    }

    /// A row's validation failure.
    private struct RowFailure: Error {
        let reason: String
    }

    /// Decodes one row. Unknown muscle groups read as Other, an unknown
    /// metric as the unit's metric (else weight), and a blank value as "done".
    private static func decodeRow(_ fields: [String], header: CSVTable.Header) -> Result<TrainingRecord.Strength, RowFailure> {
        func field(_ names: String...) -> String? { header.value(names, in: fields) }

        let dateString = field("date") ?? ""
        guard let date = WorkoutCSV.parseDate(dateString) else {
            return .failure(RowFailure(reason: "invalid date '\(dateString)'"))
        }
        let name = CSVTable.nonEmpty(field("lift"))
        let liftID = CSVTable.nonEmpty(field("lift_id"))
        guard name != nil || liftID != nil else {
            return .failure(RowFailure(reason: "missing lift"))
        }
        let liftName = name ?? String(liftID!.trimmingPrefix(StrengthLiftKey.namePrefix))

        let unitText = (CSVTable.nonEmpty(field("unit")) ?? "").lowercased()
        let unitInfo = parseUnit(unitText)
        let liftMetric = CSVTable.nonEmpty(field("metric")).flatMap { LiftMetric(rawValue: $0.lowercased()) }
            ?? unitInfo?.metric ?? .weight

        var value: Double?
        if let valueText = CSVTable.nonEmpty(field("value")) {
            guard let display = parseValue(valueText) else {
                return .failure(RowFailure(reason: "invalid value '\(valueText)'"))
            }
            let usesMetricUnit = unitInfo?.metric == liftMetric ? unitInfo?.isMetric ?? false : false
            value = liftMetric.storedValue(fromDisplay: display, metric: usesMetricUnit)
        }

        let measurement = liftMetric.usesMeasurement
            ? CSVTable.nonEmpty(field("measurement")).flatMap(parseMeasurement)
            : nil

        return .success(TrainingRecord.Strength(
            externalID: CSVTable.nonEmpty(field("id")),
            date: date,
            liftKey: liftID ?? StrengthLiftKey.make(libraryID: nil, name: liftName),
            liftName: liftName,
            muscleGroup: CSVTable.nonEmpty(field("muscle_group")).flatMap(parseMuscleGroup) ?? .other,
            metric: liftMetric,
            value: value,
            measurement: measurement,
            isLight: CSVTable.bool(field("light"), default: false),
            notes: field("notes") ?? "",
            countsTowardTraining: CSVTable.bool(field("counts_toward_training"), default: true)
        ))
    }

    /// The metric a unit implies and whether it is the metric-system one.
    static func parseUnit(_ unit: String) -> (metric: LiftMetric, isMetric: Bool)? {
        switch unit {
        case "lb", "lbs", "pound", "pounds": return (.weight, false)
        case "kg", "kgs", "kilogram", "kilograms": return (.weight, true)
        case "rep", "reps": return (.reps, false)
        case "s", "sec", "secs", "second", "seconds": return (.time, false)
        case "yd", "yds", "yard", "yards": return (.distance, false)
        case "m", "meter", "meters", "metre", "metres": return (.distance, true)
        default: return nil
        }
    }

    /// A number, or a clock time ("1:30" → 90, "1:02:03" → 3723).
    static func parseValue(_ text: String) -> Double? {
        if text.contains(":") {
            let parts = text.split(separator: ":").map { Double($0) }
            guard parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.reduce(0) { $0 * 60 + $1! }
        }
        return Double(text)
    }

    /// A measurement by raw value or display name ("lastSet", "Last Set").
    static func parseMeasurement(_ text: String) -> LiftMeasurement? {
        let key = text.lowercased().replacingOccurrences(of: " ", with: "")
        return LiftMeasurement.allCases.first { $0.rawValue.lowercased() == key }
    }

    /// A muscle group by display name, any case.
    static func parseMuscleGroup(_ text: String) -> MuscleGroup? {
        MuscleGroup.allCases.first { $0.rawValue.lowercased() == text.lowercased() }
    }
}
