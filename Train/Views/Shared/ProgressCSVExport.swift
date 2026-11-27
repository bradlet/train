//
//  ProgressCSVExport.swift
//  Train
//
//  The one-off CSV export in each Progress segment's toolbar (#23): Cardio →
//  Progress exports the cardio file, Strength → Progress the strength file.
//  The full pair, import and auto-export live in Settings → Connections.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Adds an "Export CSV" toolbar button for one discipline.
private struct ProgressCSVExportModifier: ViewModifier {
    let kind: TrainingCSVKind

    @Environment(\.modelContext) private var modelContext
    @State private var document: WorkoutCSVDocument?
    @State private var filename = ""
    @State private var isExporting = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        prepare()
                    } label: {
                        Label(kind == .cardio ? "Export Cardio CSV" : "Export Strength CSV", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("progress.exportCSV")
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: .commaSeparatedText,
                defaultFilename: filename
            ) { result in
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
            .alert(
                "Export failed",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { Text($0) }
    }

    /// Reads the snapshot and opens the exporter.
    private func prepare() {
        do {
            let file = TrainingCSVBundle.file(kind, for: try TrainingSnapshot.load(from: modelContext), on: Date())
            document = WorkoutCSVDocument(text: file.text)
            filename = (file.name as NSString).deletingPathExtension
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// Adds the Progress segment's CSV export for one discipline. Apply
    /// inside the tab host's `NavigationStack`.
    func progressCSVExport(_ kind: TrainingCSVKind) -> some View {
        modifier(ProgressCSVExportModifier(kind: kind))
    }
}
