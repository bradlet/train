//
//  CSVTable.swift
//  Train
//
//  RFC 4180 plumbing shared by the cardio and strength CSV codecs:
//  tokenizing (quoted fields with embedded commas, quotes and newlines),
//  escaping, and a header that finds columns by name. Pure; no SwiftData.
//

import Foundation

/// Shared CSV tokenizing, escaping and header lookup.
enum CSVTable {

    /// One logical CSV record after field splitting. `startLine` is the
    /// 1-based line number in the source text, so a quoted field with an
    /// embedded newline still reports where its record began.
    struct Record: Equatable {
        var fields: [String]
        var startLine: Int

        /// Whether this is a blank line (a single empty field).
        var isBlank: Bool { fields.count == 1 && fields[0].trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// A header row that finds columns by name. Names are compared after
    /// trimming, lowercasing and turning spaces into underscores, so
    /// "Perceived Exertion" finds `perceived_exertion`.
    struct Header: Equatable {
        /// Column index by normalized name. The first occurrence wins.
        let indexByName: [String: Int]

        /// Builds the lookup from a header record's fields.
        /// - Parameter fields: The header's raw field texts.
        init(_ fields: [String]) {
            var index: [String: Int] = [:]
            for (offset, field) in fields.enumerated() {
                let name = Header.normalize(field)
                if !name.isEmpty, index[name] == nil { index[name] = offset }
            }
            indexByName = index
        }

        /// Whether the header has a column with this name.
        /// - Parameter name: A column name, in any case.
        func contains(_ name: String) -> Bool {
            indexByName[Header.normalize(name)] != nil
        }

        /// The first of `names` the header has, so a legacy alias can stand
        /// in for a column's current name.
        /// - Parameter names: Candidate names, preferred first.
        /// - Returns: That column's index, or `nil` when none is present.
        func index(of names: [String]) -> Int? {
            for name in names {
                if let index = indexByName[Header.normalize(name)] { return index }
            }
            return nil
        }

        /// A record's value for a column.
        /// - Parameters:
        ///   - names: The column's name, then any legacy aliases.
        ///   - fields: The record's fields.
        /// - Returns: The raw field, `""` when the record is too short for
        ///   it, or `nil` when the header has no such column.
        func value(_ names: [String], in fields: [String]) -> String? {
            guard let index = index(of: names) else { return nil }
            return index < fields.count ? fields[index] : ""
        }

        /// Trimmed, lowercased, spaces as underscores.
        static func normalize(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }
    }

    // MARK: - Writing

    /// Joins escaped rows into a CSV document ending with a newline.
    /// - Parameter rows: The rows, header first.
    static func document(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 field escape: wrap in quotes if the field contains a comma,
    /// quote, or newline; double any embedded quotes.
    static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Reading

    /// Tokenizes a CSV document into records, handling RFC 4180 quoted
    /// fields with embedded commas, quotes, and newlines. A leading
    /// byte-order mark is dropped.
    static func tokenize(_ csv: String) -> [Record] {
        var records: [Record] = []
        var currentFields: [String] = []
        var currentField = ""
        var inQuotes = false
        var line = 1
        var recordStartLine = 1

        var chars = Array(csv)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                if c == "\"" {
                    // Doubled quote inside a quoted field → literal quote.
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                if c == "\n" || c == "\r\n" { line += 1 }
                currentField.append(c)
                i += 1
                continue
            }

            switch c {
            case "\"":
                inQuotes = true
                i += 1
            case ",":
                currentFields.append(currentField)
                currentField = ""
                i += 1
            case "\r\n", "\r", "\n":
                // Swift treats \r\n as a single Character (grapheme cluster),
                // so it must be its own case alongside standalone \r and \n.
                currentFields.append(currentField)
                records.append(Record(fields: currentFields, startLine: recordStartLine))
                currentFields = []
                currentField = ""
                line += 1
                recordStartLine = line
                i += 1
            default:
                currentField.append(c)
                i += 1
            }
        }

        // Flush trailing field/record (file may not end with a newline).
        if !currentField.isEmpty || !currentFields.isEmpty {
            currentFields.append(currentField)
            records.append(Record(fields: currentFields, startLine: recordStartLine))
        }

        return records
    }

    /// Parses a lenient boolean: "true", "yes" and "1" (any case) are true.
    /// - Parameters:
    ///   - raw: The field text, or `nil` when the column is absent.
    ///   - default: The value for an absent or blank field.
    static func bool(_ raw: String?, default defaultValue: Bool) -> Bool {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return defaultValue }
        if ["true", "yes", "1"].contains(trimmed) { return true }
        if ["false", "no", "0"].contains(trimmed) { return false }
        return defaultValue
    }

    /// A trimmed field, or `nil` when absent or blank.
    static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
