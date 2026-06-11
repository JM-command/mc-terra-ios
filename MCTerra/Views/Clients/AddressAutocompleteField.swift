//
//  AddressAutocompleteField.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import SwiftUI
import MapKit
import Combine

/// Encapsule un `MKLocalSearchCompleter` configuré pour l'autocomplétion d'adresses
/// postales (couverture mondiale, sans biais de région ni permission de localisation).
final class AddressSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    /// Suggestions d'adresses renvoyées par le completer, prêtes à afficher.
    @Published var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Adresses uniquement (pas de points d'intérêt / commerces).
        completer.resultTypes = .address
    }

    /// Met à jour la requête : une chaîne vide vide les suggestions.
    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.suggestions = results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}

/// Champ de saisie d'adresse avec autocomplétion mondiale via MapKit.
///
/// La frappe libre est toujours conservée (le binding `address` est mis à jour à
/// chaque caractère), et une petite liste de suggestions apparaît sous le champ
/// tant qu'il a le focus. Un tap remplit l'adresse avec "title, subtitle".
struct AddressAutocompleteField: View {
    @Binding var address: String

    @StateObject private var model = AddressSearchModel()
    @FocusState private var isFocused: Bool
    /// État texte local : pilote le `TextField` et déclenche les requêtes.
    @State private var text: String = ""

    /// Nombre maximum de suggestions affichées sous le champ.
    private let maxSuggestions = 5

    var body: some View {
        // Le champ et ses suggestions sont des lignes séparées d'une même Section.
        TextField("Adresse", text: $text, axis: .vertical)
            .textContentType(.fullStreetAddress)
            .lineLimit(2...4)
            .focused($isFocused)
            .onChange(of: text) { _, newValue in
                // Frappe libre conservée même sans suggestion.
                address = newValue
                model.update(query: newValue)
            }
            .onAppear {
                // Pré-remplit le champ avec l'adresse déjà saisie (édition).
                if text.isEmpty {
                    text = address
                }
            }

        if isFocused, !model.suggestions.isEmpty {
            ForEach(model.suggestions.prefix(maxSuggestions), id: \.self) { completion in
                Button {
                    select(completion)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: completion.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !completion.subtitle.isEmpty {
                            Text(verbatim: completion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Concatène proprement title + subtitle, remplit le champ, vide les suggestions
    /// et retire le focus.
    private func select(_ completion: MKLocalSearchCompletion) {
        let parts = [completion.title, completion.subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let full = parts.joined(separator: ", ")
        text = full
        address = full
        model.update(query: "")
        isFocused = false
    }
}

#Preview {
    @Previewable @State var address = ""
    return Form {
        Section("Coordonnées") {
            AddressAutocompleteField(address: $address)
        }
    }
}
