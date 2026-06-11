//
//  ForfaitsView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// Lists Marta's forfaits and lets her add, edit or remove them. Sessions copy a
/// forfait's name/duration/price at creation, so changes here never touch past
/// sessions.
struct ForfaitsView: View {
    @Environment(\.modelContext) private var context

    /// Sorted by manual order first, then name for a stable display.
    @Query(sort: [SortDescriptor(\Forfait.sortOrder), SortDescriptor(\Forfait.name)])
    private var forfaits: [Forfait]

    /// Drives the create sheet (a brand-new forfait, no model yet).
    @State private var showNewEditor = false
    /// The forfait being edited, when a row is tapped.
    @State private var editingForfait: Forfait?

    var body: some View {
        List {
            Section {
                ForEach(forfaits) { forfait in
                    Button {
                        editingForfait = forfait
                    } label: {
                        ForfaitRow(forfait: forfait)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: deleteForfaits)
            } footer: {
                Text("Les forfaits pré-remplissent la durée et le prix d'une nouvelle séance. Les séances déjà créées ne changent pas.")
            }
        }
        .navigationTitle("Mes forfaits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewEditor = true
                } label: {
                    Label("Ajouter un forfait", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewEditor) {
            ForfaitEditorView(forfait: nil, nextSortOrder: nextSortOrder)
        }
        .sheet(item: $editingForfait) { forfait in
            ForfaitEditorView(forfait: forfait, nextSortOrder: nextSortOrder)
        }
    }

    /// The order a brand-new forfait should take (placed at the end of the list).
    private var nextSortOrder: Int {
        (forfaits.map(\.sortOrder).max() ?? -1) + 1
    }

    private func deleteForfaits(at offsets: IndexSet) {
        for index in offsets {
            context.delete(forfaits[index])
        }
        try? context.save()
    }
}

// MARK: - Row

/// A single forfait line: name on top, duration and price below.
private struct ForfaitRow: View {
    let forfait: Forfait

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: forfait.name)
                .font(.body)
            Text(verbatim: subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "1 h 00 · 80 CHF" style summary.
    private var subtitle: String {
        let duration = formatDuration(forfait.durationMinutes)
        let price = forfait.priceCHF == 0
            ? String(localized: "Gratuit")
            : "\(formatPrice(forfait.priceCHF)) CHF"
        return "\(duration) · \(price)"
    }

    private func formatDuration(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours) h \(String(format: "%02d", mins))"
        } else {
            return "\(mins) min"
        }
    }

    /// Drops trailing ".0" for whole prices (80 instead of 80.0).
    private func formatPrice(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value)
    }
}

// MARK: - Editor

/// Create or edit a single forfait. Passing `forfait: nil` creates a new one
/// (placed at `nextSortOrder`); passing an existing model edits it in place.
struct ForfaitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Existing forfait being edited, or `nil` when creating.
    let forfait: Forfait?
    /// Order assigned to a newly-created forfait so it lands at the list's end.
    let nextSortOrder: Int

    @State private var name: String
    @State private var durationHours: Int
    @State private var durationMins: Int
    @State private var priceCHF: Double

    init(forfait: Forfait?, nextSortOrder: Int) {
        self.forfait = forfait
        self.nextSortOrder = nextSortOrder
        if let forfait {
            _name = State(initialValue: forfait.name)
            _durationHours = State(initialValue: forfait.durationMinutes / 60)
            _durationMins = State(initialValue: forfait.durationMinutes % 60)
            _priceCHF = State(initialValue: forfait.priceCHF)
        } else {
            _name = State(initialValue: "")
            _durationHours = State(initialValue: 1)
            _durationMins = State(initialValue: 0)
            _priceCHF = State(initialValue: 0)
        }
    }

    private var isEditing: Bool { forfait != nil }

    private var navigationTitle: LocalizedStringKey {
        isEditing ? "Modifier le forfait" : "Nouveau forfait"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var durationMinutes: Int {
        durationHours * 60 + durationMins
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Forfait") {
                    TextField("Nom", text: $name)
                }

                Section("Durée") {
                    Picker("Heures", selection: $durationHours) {
                        ForEach(0...23, id: \.self) { hour in
                            Text("\(hour) h").tag(hour)
                        }
                    }
                    Picker("Minutes", selection: $durationMins) {
                        ForEach([0, 5, 10, 15, 20, 30, 45], id: \.self) { minute in
                            Text("\(String(format: "%02d", minute)) min").tag(minute)
                        }
                    }
                }

                Section("Prix") {
                    HStack {
                        Text("Prix")
                        Spacer()
                        TextField("Prix", value: $priceCHF, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 100)
                        Text(verbatim: "CHF")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let forfait {
            forfait.name = trimmedName
            forfait.durationMinutes = durationMinutes
            forfait.priceCHF = priceCHF
        } else {
            let new = Forfait(
                name: trimmedName,
                durationMinutes: durationMinutes,
                priceCHF: priceCHF,
                sortOrder: nextSortOrder
            )
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ForfaitsView()
    }
    .modelContainer(for: [Client.self, Seance.self, Forfait.self], inMemory: true)
}
