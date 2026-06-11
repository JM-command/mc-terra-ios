//
//  NewClientView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit

/// Sheet to create a new client and save it locally.
struct NewClientView: View {
    @Environment(\.dismiss) private var dismiss
    // The SwiftData "place" where we insert the new client.
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var language = "fr"

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    TextField("Nom", text: $name)
                    TextField("Téléphone", text: $phone)
                        .keyboardType(.phonePad)
                    Picker("Langue", selection: $language) {
                        Text(verbatim: "Français").tag("fr")
                        Text(verbatim: "Português").tag("pt")
                    }
                }
                Section("Coordonnées") {
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    AddressAutocompleteField(address: $address)
                }
            }
            .navigationTitle("Nouveau client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let client = Client(
            name: name.trimmingCharacters(in: .whitespaces),
            phone: phone,
            email: email.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language
        )
        context.insert(client)
        // Reflect the new client in the home-screen widgets.
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

#Preview {
    NewClientView()
        .modelContainer(for: Client.self, inMemory: true)
}
