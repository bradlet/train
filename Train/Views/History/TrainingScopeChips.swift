//
//  TrainingScopeChips.swift
//  Train
//
//  The scope chip row at the top of Cardio → Progress (#17): All, then each
//  family present. Long-press a family chip to drill into one of its types
//  (Running → Tempo Run); a type scope shows as its own chip with a clear
//  button. The selection is sticky (`@AppStorage` in `HistoryView`).
//

import SwiftUI

/// Scope chips for a Progress segment.
struct TrainingScopeChips: View {
    @Binding var scope: TrainingScope
    /// The exercises the chips are offered for.
    let exercises: [Exercise]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, title: "All", systemImage: nil, tint: .blue)
                ForEach(TrainingScope.families(in: exercises)) { family in
                    familyChip(family)
                }
                if case .type(let type) = scope {
                    Button {
                        scope = .family(type.family)
                    } label: {
                        HStack(spacing: 4) {
                            Text(type.rawValue)
                            Image(systemName: "xmark.circle.fill")
                        }
                        .chipStyle(selected: true, tint: type.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progressScope.type.\(type.rawValue)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("progressScope.chips")
    }

    /// A family chip; its menu drills into the family's types.
    private func familyChip(_ family: ExerciseFamily) -> some View {
        let types = TrainingScope.types(of: family, in: exercises)
        return chip(.family(family), title: family.rawValue, systemImage: family.systemImage, tint: family.types.first?.color ?? .blue)
            .contextMenu {
                if types.count > 1 {
                    ForEach(types) { type in
                        Button(type.rawValue) { scope = .type(type) }
                    }
                }
            }
    }

    private func chip(_ value: TrainingScope, title: String, systemImage: String?, tint: Color) -> some View {
        // A family chip stays lit while one of its types is drilled into.
        let selected = value == .all ? scope == .all : scope.family == value.family
        return Button {
            scope = value
        } label: {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .chipStyle(selected: selected, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progressScope.\(value.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension View {
    /// The shared capsule chip look.
    func chipStyle(selected: Bool, tint: Color) -> some View {
        self
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? tint : tint.opacity(0.12)))
            .foregroundStyle(selected ? .white : tint)
    }
}
