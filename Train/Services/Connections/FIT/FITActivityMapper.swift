//
//  FITActivityMapper.swift
//  Train
//
//  Turns a decoded FIT activity into cardio records (#22): one per `session`
//  message, so a multisport file yields one workout per leg. Strength
//  sessions are left out (Train records a lift's number per session, not a
//  watch's timed session), as are transitions. Intensity is never inferred:
//  key and training inclusion come from the athlete's own defaults.
//

import Foundation

/// What a FIT file holds, ready to import.
struct FITActivityImport: Equatable, Sendable {
    /// One record per importable session.
    var records: [TrainingRecord.Cardio] = []
    /// Strength-training sessions left out.
    var skippedStrength = 0
}

/// FIT activity → interchange records.
enum FITActivityMapper {

    /// FIT global message numbers used here.
    enum Message {
        static let fileID: UInt16 = 0
        static let session: UInt16 = 18
    }

    /// `session` field numbers used here.
    enum SessionField {
        static let startTime: UInt8 = 2
        static let sport: UInt8 = 5
        static let subSport: UInt8 = 6
        static let totalElapsedTime: UInt8 = 7   // s × 1000
        static let totalTimerTime: UInt8 = 8     // s × 1000
        static let totalDistance: UInt8 = 9      // m × 100
    }

    /// `file_id` field numbers used here.
    enum FileIDField {
        static let serialNumber: UInt8 = 3
        static let timeCreated: UInt8 = 4
    }

    /// Metres per mile.
    private static let metersPerMile = 1609.344

    /// What a FIT sport is, for import.
    enum SportMapping: Equatable {
        case cardio(ExerciseType)
        case strength
        case skip
    }

    /// Maps a FIT sport and sub-sport. Running of every kind is plain Run:
    /// FIT doesn't say whether it was easy or hard, and Train never guesses.
    /// - Parameters:
    ///   - sport: FIT `sport` enum value.
    ///   - subSport: FIT `sub_sport` enum value, if any.
    static func mapping(sport: Int, subSport: Int?) -> SportMapping {
        switch sport {
        case 1: return .cardio(.run)                         // running
        case 2: return .cardio(.bike)                        // cycling
        case 3: return .skip                                 // transition
        case 5: return .cardio(.swim)                        // swimming
        case 11: return .cardio(.walk)                       // walking
        case 17: return .cardio(.hike)                       // hiking
        case 4: return subSport == 15 ? .cardio(.elliptical) : .cardio(.other) // fitness equipment
        case 10: return subSport == 20 ? .strength : .cardio(.other)            // training
        default: return .cardio(.other)
        }
    }

    /// Maps a decoded file's sessions.
    /// - Parameters:
    ///   - messages: The decoded messages.
    ///   - defaults: The athlete's inclusion and key defaults.
    static func activity(from messages: [FITMessage], defaults: ImportDefaults) -> FITActivityImport {
        let fileID = messages.first { $0.globalNumber == Message.fileID }
        let sessions = messages.filter { $0.globalNumber == Message.session }
        var result = FITActivityImport()
        for (index, session) in sessions.enumerated() {
            guard let start = session[SessionField.startTime] else { continue }
            let type: ExerciseType
            switch mapping(sport: Int(session[SessionField.sport] ?? 0), subSport: session[SessionField.subSport].map(Int.init)) {
            case .cardio(let mapped): type = mapped
            case .strength:
                result.skippedStrength += 1
                continue
            case .skip:
                continue
            }
            let seconds = (session[SessionField.totalTimerTime] ?? session[SessionField.totalElapsedTime] ?? 0) / 1000
            let meters = (session[SessionField.totalDistance] ?? 0) / 100
            result.records.append(TrainingRecord.Cardio(
                externalID: externalID(fileID: fileID, sessionStart: start, index: index),
                source: WorkoutSource.garmin.rawValue,
                date: FITDecoder.date(fromFIT: start),
                name: type.rawValue,
                type: type,
                durationSeconds: Int(seconds.rounded()),
                distanceMiles: meters / metersPerMile,
                countsTowardTraining: TrainingInclusion.counts(type, excluded: defaults.trainingExcludedTypes),
                isKeyWorkout: KeyWorkoutDefaults.isKey(type, keyTypes: defaults.keyWorkoutTypes)
            ))
        }
        return result
    }

    /// A stable anchor: the device serial and the file's creation time
    /// (falling back to the session start), plus the session's position, so
    /// importing the same file again is recognised.
    static func externalID(fileID: FITMessage?, sessionStart: Double, index: Int) -> String {
        let serial = fileID?[FileIDField.serialNumber].map { String(Int64($0)) } ?? "0"
        let created = fileID?[FileIDField.timeCreated] ?? sessionStart
        return "fit:\(serial):\(Int64(created)):\(index)"
    }
}
