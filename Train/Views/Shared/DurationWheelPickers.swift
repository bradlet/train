//
//  DurationWheelPickers.swift
//  Train
//
//  Shared hours/minutes/seconds wheel-picker row used by every cardio
//  duration editor (workout forms, exercise scheduling, planned targets,
//  favorites), headed by quick-pick pills for common session lengths.
//

import SwiftUI

/// A common cardio session length offered as a one-tap pill above the
/// duration wheels. Picking one sets the wheels; the athlete fine-tunes
/// from there.
struct DurationPreset: Identifiable, Equatable {
    /// The preset's length in whole minutes.
    let minutes: Int

    var id: Int { minutes }

    /// The pills shown above every duration editor, shortest first.
    static let common: [DurationPreset] = [30, 45, 60].map(DurationPreset.init(minutes:))

    /// The pill's label in minutes, e.g. "30m" or "60m", so the set reads
    /// as one scale.
    var label: String { "\(minutes)m" }

    /// The preset split into the wheels' hours, minutes and seconds.
    var components: (hours: Int, minutes: Int, seconds: Int) {
        (minutes / 60, minutes % 60, 0)
    }

    /// Whether the wheels currently show exactly this preset.
    /// - Parameters:
    ///   - hours: The hours wheel's value.
    ///   - minutes: The minutes wheel's value.
    ///   - seconds: The seconds wheel's value.
    func matches(hours: Int, minutes: Int, seconds: Int) -> Bool {
        hours * 3600 + minutes * 60 + seconds == self.minutes * 60
    }
}

/// A horizontal row of three wheel pickers for entering a duration as
/// hours (0–23), minutes (0–59), and seconds (0–59), headed by the
/// `DurationPreset.common` pills. State is owned by the parent view via
/// bindings.
struct DurationWheelPickers: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    var body: some View {
        VStack(spacing: 8) {
            presetPills
            HStack {
                Picker("Hours", selection: $hours) {
                    ForEach(0..<24) { Text("\($0)h").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Picker("Minutes", selection: $minutes) {
                    ForEach(0..<60) { Text("\($0)m").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Picker("Seconds", selection: $seconds) {
                    ForEach(0..<60) { Text("\($0)s").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 120)
        }
    }

    /// One pill per common duration; the one the wheels match is filled.
    private var presetPills: some View {
        HStack(spacing: 8) {
            ForEach(DurationPreset.common) { preset in
                let isSelected = preset.matches(hours: hours, minutes: minutes, seconds: seconds)
                Button {
                    let parts = preset.components
                    withAnimation {
                        hours = parts.hours
                        minutes = parts.minutes
                        seconds = parts.seconds
                    }
                } label: {
                    Text(preset.label)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
                // Borderless so a tap on one pill doesn't fire the whole Form row.
                .buttonStyle(.borderless)
                .accessibilityLabel("\(preset.minutes) minutes")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("duration.preset.\(preset.minutes)")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

#Preview {
    @Previewable @State var hours = 0
    @Previewable @State var minutes = 30
    @Previewable @State var seconds = 0
    Form {
        Section("Duration") {
            DurationWheelPickers(hours: $hours, minutes: $minutes, seconds: $seconds)
        }
    }
}
