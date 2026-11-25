//
//  CoachSpeechService.swift
//  Train
//
//  Speech-to-text for the coach composer, plus the pure merge of dictated
//  text into whatever the athlete already typed.
//

import Foundation

/// Dictation engine behind the coach composer's mic button and the Home
/// tab's voice entry point.
///
/// Mirrors the `AICoachService` split: the live implementation wraps
/// SFSpeechRecognizer, the stub keeps previews and UI tests deterministic.
/// Injected via `@Environment(\.coachSpeech)`.
@MainActor
protocol CoachSpeechService: AnyObject {
    /// The running transcription for the current (or last) session.
    var transcript: String { get }
    /// Whether the microphone is currently capturing.
    var isRecording: Bool { get }
    /// A user-facing reason dictation could not start or stopped early.
    var errorMessage: String? { get }
    /// Requests authorization and starts capturing, streaming partial results
    /// into `transcript`. A refusal or hardware failure is reported in
    /// `errorMessage` rather than thrown — the composer stays usable for
    /// typing either way.
    func start() async
    /// Stops capturing, keeping whatever was transcribed for review.
    func stop()
    /// Clears the transcript and any error, arming the next session.
    func reset()
}

/// Pure merge of dictated text with what was already in the composer.
enum VoiceDraft {
    /// Appends the live transcript to the draft as it stood when recording
    /// began. Exactly one space joins them; a blank transcript returns the
    /// prefix untouched so starting the mic never rewrites typed text.
    static func compose(prefix: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return prefix }
        let typed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return spoken }
        return typed + " " + spoken
    }
}

/// Pure decisions behind hands-free dictation — the widget and Siri entries,
/// where the athlete speaks and never taps Send.
///
/// The chat view owns the timers; this owns what they decide, so the rules
/// are unit-testable without a microphone or a clock.
enum VoiceAutoSend {
    /// How long the transcript must sit unchanged after speech before the
    /// capture ends and the draft sends.
    static let silenceWindow: Duration = .milliseconds(1500)
    /// How long to listen without hearing anything before giving up — so a
    /// pocketed tap doesn't hold the microphone open.
    static let noSpeechTimeout: Duration = .seconds(8)

    /// What a quiet spell during capture means.
    enum CaptureAction: Equatable {
        /// Not quiet long enough yet.
        case keepListening
        /// The athlete spoke and then paused: end capture, then send.
        case finish
        /// Nothing was heard: end capture and send nothing.
        case giveUp
    }

    /// How long the capture should wait, from the latest transcript change,
    /// before re-deciding with `captureAction`.
    /// - Parameter transcript: The live transcript.
    static func quietWindow(for transcript: String) -> Duration {
        isBlank(transcript) ? noSpeechTimeout : silenceWindow
    }

    /// Decides what a quiet spell means for an in-progress capture.
    /// - Parameters:
    ///   - transcript: The live transcript.
    ///   - quietFor: How long the transcript has gone unchanged.
    static func captureAction(transcript: String, quietFor: Duration) -> CaptureAction {
        if isBlank(transcript) {
            return quietFor >= noSpeechTimeout ? .giveUp : .keepListening
        }
        return quietFor >= silenceWindow ? .finish : .keepListening
    }

    /// Whether an armed draft should send now. Waits for capture to end and
    /// for the coach to be ready — a cold launch from the widget is still
    /// loading the model while the athlete talks.
    /// - Parameters:
    ///   - draft: The composer text.
    ///   - isArmed: Whether this conversation was entered hands-free and the
    ///     draft hasn't been sent or abandoned yet.
    ///   - isRecording: Whether dictation is still capturing.
    ///   - canSend: Whether the coach can take a message right now.
    static func shouldSend(draft: String, isArmed: Bool, isRecording: Bool, canSend: Bool) -> Bool {
        isArmed && !isRecording && canSend && !isBlank(draft)
    }

    /// Whether an armed draft is finished and only waiting on the coach,
    /// which the composer surfaces as "Sends when your coach is ready".
    /// - Parameters: See `shouldSend`.
    static func isWaitingForCoach(draft: String, isArmed: Bool, isRecording: Bool, canSend: Bool) -> Bool {
        isArmed && !isRecording && !canSend && !isBlank(draft)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
