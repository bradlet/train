//
//  CoachVoiceWidget.swift
//  CoachVoiceWidget
//
//  A one-tap "talk to your coach" widget for the Home Screen and Lock Screen.
//
//  A widget can't use the microphone (widget extensions never get mic
//  access, interactive widgets included), so a tap opens the app straight
//  into the coach chat with hands-free dictation armed. The app does the
//  listening and sends the message itself after the athlete pauses.
//

import SwiftUI
import WidgetKit

/// The deep link the app parses into `CoachChatEntry.voice(autoSend: true)`.
///
/// Spelled out here because an extension can't link app code;
/// `CoachLaunchRouteTests.voiceURLOpensHandsFreeDictation` pins the same
/// literal on the app side.
enum CoachVoiceLink {
    static let url = URL(string: "hybridaithletics://coach/voice")!
}

/// The widget has no data: one static entry, never refreshed.
struct CoachVoiceEntry: TimelineEntry {
    let date: Date
}

/// Supplies the single static entry.
struct CoachVoiceProvider: TimelineProvider {
    /// The placeholder shown while the widget gallery loads.
    func placeholder(in context: Context) -> CoachVoiceEntry {
        CoachVoiceEntry(date: .now)
    }

    /// The gallery snapshot.
    func getSnapshot(in context: Context, completion: @escaping (CoachVoiceEntry) -> Void) {
        completion(CoachVoiceEntry(date: .now))
    }

    /// A one-entry timeline that never reloads — nothing on it changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachVoiceEntry>) -> Void) {
        completion(Timeline(entries: [CoachVoiceEntry(date: .now)], policy: .never))
    }
}

/// The widget's face for each supported family.
struct CoachVoiceWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(CoachVoiceLink.url)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Talk to your coach")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI Coach")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Tap and talk")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 52))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("Talk to your coach")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Tap, speak, done")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.42, blue: 0.95), Color(red: 0.35, green: 0.22, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Home Screen + Lock Screen "talk to your coach" button.
struct CoachVoiceWidget: Widget {
    static let kind = "CoachVoiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CoachVoiceProvider()) { _ in
            CoachVoiceWidgetView()
        }
        .configurationDisplayName("Talk to Your Coach")
        .description("Tap to open your AI coach already listening. Speak, pause, and it sends.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

/// The extension's entry point.
@main
struct CoachVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoachVoiceWidget()
    }
}

#Preview(as: .systemSmall) {
    CoachVoiceWidget()
} timeline: {
    CoachVoiceEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    CoachVoiceWidget()
} timeline: {
    CoachVoiceEntry(date: .now)
}
