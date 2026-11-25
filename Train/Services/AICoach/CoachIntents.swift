//
//  CoachIntents.swift
//  Train
//
//  Siri / Shortcuts entry to the coach: "Tell my AI coach…" and "Talk to my
//  AI coach". Both open the app and route through `CoachLaunchRouter`, the
//  same path the home-screen widget's deep link takes.
//

import AppIntents

/// "Tell my AI coach": Siri asks for the message and transcribes it, then the
/// app opens with that message already sending to the coach.
struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell My Coach"
    static let description = IntentDescription(
        "Send a message to your AI coach — describe a workout, or ask about your training."
    )
    /// The coach runs in the app, so the app has to come forward.
    static let openAppWhenRun = true

    /// What to tell the coach. Siri asks for it when the phrase didn't carry it.
    @Parameter(title: "Message", requestValueDialog: "What should I tell your coach?")
    var message: String

    init() {}

    /// Creates the intent with its message already filled.
    /// - Parameter message: What to tell the coach.
    init(message: String) {
        self.message = message
    }

    /// Routes the message to the coach chat. A blank message just opens the
    /// conversation rather than sending nothing.
    func perform() async throws -> some IntentResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        await CoachLaunchRouter.shared.route(trimmed.isEmpty ? .standard : .message(trimmed))
        return .result()
    }
}

/// "Talk to my AI coach": the widget's behavior by voice — opens the coach
/// already listening, and sends once the athlete pauses.
struct TalkToCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to My Coach"
    static let description = IntentDescription(
        "Open your AI coach already listening. Speak, pause, and it sends."
    )
    static let openAppWhenRun = true

    init() {}

    /// Routes a hands-free voice entry to the coach chat.
    func perform() async throws -> some IntentResult {
        await CoachLaunchRouter.shared.route(.voice(autoSend: true))
        return .result()
    }
}

/// The Siri phrases.
///
/// Every App Shortcut phrase must contain `\(.applicationName)`, and nobody
/// wants to say "Tell my Train" to Siri. `INAlternativeAppNames` in
/// `Info.plist` registers "AI Coach", "Coach" and "Train Coach" as synonyms Siri accepts in
/// that slot — so "Tell my \(.applicationName)" is said "Tell my AI coach".
/// The athlete can also rename a shortcut in the Shortcuts app to any phrase.
struct CoachShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskCoachIntent(),
            phrases: [
                "Tell my \(.applicationName)",
                "Ask my \(.applicationName)",
                "Message my \(.applicationName)",
            ],
            shortTitle: "Tell My Coach",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
        AppShortcut(
            intent: TalkToCoachIntent(),
            phrases: [
                "Talk to my \(.applicationName)",
                "Open my \(.applicationName)",
            ],
            shortTitle: "Talk to My Coach",
            systemImageName: "mic.fill"
        )
    }
}
