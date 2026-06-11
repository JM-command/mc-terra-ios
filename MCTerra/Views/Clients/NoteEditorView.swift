//
//  NoteEditorView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import SwiftUI
import SwiftData

/// Éditeur plein écran d'une note, façon bloc-notes (Notes Apple) : un grand
/// `TextEditor` lié au texte de la note. On met à jour `updatedAt` et on sauve à
/// la disparition et au bouton "Enregistrer".
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Note SwiftData ; les edits sur `note.text` sont liés directement.
    @Bindable var note: Note

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $note.text)
            .focused($isFocused)
            .font(.body)
            .padding(.horizontal)
            .scrollContentBackground(.hidden)
            .navigationTitle(Text(note.createdAt, format: .dateTime.day().month().year().hour().minute()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { persist(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { isFocused = false }
                }
            }
            .onAppear {
                // Note vide (création) : on ouvre directement le clavier.
                if note.text.isEmpty { isFocused = true }
            }
            .onDisappear { persist() }
    }

    /// Met à jour la date de modification et sauve le contexte.
    private func persist() {
        note.updatedAt = .now
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        NoteEditorView(note: Note(text: "Exemple de note pour l'aperçu.", author: "marta"))
    }
    .modelContainer(for: [Client.self, Seance.self, Note.self], inMemory: true)
}
