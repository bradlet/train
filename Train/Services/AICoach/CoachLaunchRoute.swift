//
//  CoachLaunchRoute.swift
//  Hybrid AIthletics
//
//  How the coach chat is entered, and the deep links that open it from
//  outside the app — the home-screen widget and the Siri shortcuts.
//

import Foundation

/// How a coach conversation is entered.
///
/// The Home tab's card opens `.standard`; its mic button opens
/// `.voice(autoSend: false)` (the athlete reviews the draft and taps Send).
/// Entries from outside the app — the widget and Siri — are hands-free:
/// `.voice(autoSend: true)` sends after a pause, and `.message` sends text
/// Siri already transcribed.
enum CoachChatEntry: Hashable {
    /// Open the conversation as-is.
    case standard
    /// Start dictating on appear. With `autoSend`, the draft sends itself
    /// once the athlete pauses or stops the mic.
    case voice(autoSend: Bool)
    /// Send this message as soon as the coach is ready.
    case message(String)

    /// Whether the chat should start dictating as soon as it appears.
    var startsWithVoice: Bool {
        if case .voice = self { return true }
        return false
    }

    /// Whether dictated or supplied text sends without a Send tap.
    var sendsAutomatically: Bool {
        switch self {
        case .standard: false
        case .voice(let autoSend): autoSend
        case .message: true
        }
    }
}

/// Parses and builds the app's `com.bradlet.train://coach…` deep links.
///
/// - `com.bradlet.train://coach/voice` → `.voice(autoSend: true)` (the widget)
/// - `com.bradlet.train://coach?message=…` → `.message(…)`
///
/// The widget extension spells the voice URL out literally (it cannot link
/// app code); `CoachLaunchRouteTests` pins that literal.
enum CoachLaunchRoute {
    /// The URL scheme registered in `Info.plist`.
    static let scheme = "com.bradlet.train"
    /// The host every coach link uses.
    static let host = "coach"

    /// The coach entry a URL asks for, or `nil` when it isn't a coach link
    /// (for example the Google sign-in redirect) or carries no usable message.
    /// - Parameter url: The URL the app was opened with.
    static func entry(from url: URL) -> CoachChatEntry? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        switch url.path.lowercased() {
        case "/voice":
            return .voice(autoSend: true)
        case "", "/":
            let message = components.queryItems?
                .first { $0.name == "message" }?
                .value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty ? nil : .message(message)
        default:
            return nil
        }
    }

    /// The deep link that opens `entry` from outside the app, or `nil` for an
    /// entry no link expresses (`.standard`, in-app review-first voice, or a
    /// blank message).
    /// - Parameter entry: The entry to encode.
    static func url(for entry: CoachChatEntry) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        switch entry {
        case .voice(autoSend: true):
            components.path = "/voice"
        case .message(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            components.queryItems = [URLQueryItem(name: "message", value: trimmed)]
        case .standard, .voice(autoSend: false):
            return nil
        }
        return components.url
    }
}

/// App-scope handoff from an external launch (deep link or App Intent) to
/// the Home tab, which owns the navigation into the coach chat.
///
/// Not a ViewModel: it owns no queries and makes no view decisions — it only
/// holds the one entry waiting to be acted on. `shared` exists because an
/// App Intent's `perform()` has no access to the SwiftUI environment.
@MainActor
@Observable
final class CoachLaunchRouter {
    /// The instance the app injects and App Intents route through.
    static let shared = CoachLaunchRouter()

    /// The entry waiting to be opened, if any. A later launch replaces an
    /// earlier one that was never consumed.
    private(set) var pending: CoachChatEntry?

    /// Queues an entry for the Home tab to open.
    /// - Parameter entry: The entry to open.
    func route(_ entry: CoachChatEntry) {
        pending = entry
    }

    /// Takes the pending entry, clearing it so it opens exactly once.
    /// - Returns: The entry that was pending, if any.
    @discardableResult
    func consume() -> CoachChatEntry? {
        defer { pending = nil }
        return pending
    }
}
