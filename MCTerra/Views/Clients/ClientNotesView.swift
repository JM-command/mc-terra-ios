//
//  ClientNotesView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import SwiftUI
import SwiftData

/// Page listant TOUTES les notes horodatées d'un client (la plus récente en haut).
/// Chaque ligne : date/heure, badge auteur (Marta / IA) et un aperçu du texte.
/// Le "+" crée une note vide et ouvre l'éditeur ; le swipe supprime ; le tap édite.
struct ClientNotesView: View {
    @Environment(\.modelContext) private var context
    @Bindable var client: Client

    /// La note vide qu'on vient de créer, à ouvrir aussitôt dans l'éditeur.
    @State private var newlyCreated: Note?

    /// Notes triées de la plus récente à la plus ancienne.
    private var sortedNotes: [Note] {
        client.noteEntries.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if sortedNotes.isEmpty {
                ContentUnavailableView {
                    Label("Aucune note", systemImage: "note.text")
                } description: {
                    Text("Ajoute la première note de ce client avec le bouton +.")
                }
            } else {
                List {
                    ForEach(sortedNotes) { note in
                        NavigationLink {
                            NoteEditorView(note: note)
                        } label: {
                            NoteRow(note: note)
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .navigationTitle(Text(verbatim: client.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addNote()
                } label: {
                    Label("Nouvelle note", systemImage: "plus")
                }
            }
        }
        // Ouvre l'éditeur sur la note tout juste créée.
        .navigationDestination(item: $newlyCreated) { note in
            NoteEditorView(note: note)
        }
    }

    /// Crée une note vide (auteur "marta"), la rattache au client et l'ouvre.
    private func addNote() {
        let note = Note(author: "marta", client: client)
        context.insert(note)
        try? context.save()
        newlyCreated = note
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedNotes[index])
        }
        try? context.save()
    }
}

/// Une ligne de la liste : date/heure + badge auteur + aperçu du texte.
private struct NoteRow: View {
    let note: Note

    private var preview: String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Note vide" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                NoteAuthorBadge(author: NoteAuthor(stored: note.author))
            }
            Text(verbatim: preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

/// Petit badge coloré indiquant l'auteur de la note (Marta ou IA).
private struct NoteAuthorBadge: View {
    let author: NoteAuthor

    private var tint: Color {
        switch author {
        case .marta: return .blue
        case .ia: return .purple
        }
    }

    var body: some View {
        Text(verbatim: author.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview {
    NavigationStack {
        ClientNotesView(client: Client(name: "Marta Coelho"))
    }
    .modelContainer(for: [Client.self, Seance.self, Note.self], inMemory: true)
}
