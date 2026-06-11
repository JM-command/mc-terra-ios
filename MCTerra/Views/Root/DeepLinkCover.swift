//
//  DeepLinkCover.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  The screen presented full-screen when a `mcterra://` deep link (from a widget)
//  resolves to a route. Each route fetches its target by the model's stable `uuid`
//  and shows the matching detail view inside a `NavigationStack` with a "Fermer"
//  button. Missing targets show a friendly "introuvable" message instead of
//  crashing.

import SwiftUI
import SwiftData

/// Resolves a `DeepLinkRoute` to a destination view, wrapped in a closable
/// navigation stack. Kept as its own view so the routing logic stays out of
/// `ContentView` and the type-checker has a small body to chew on.
struct DeepLinkCover: View {
    let route: DeepLinkRoute
    /// Called when the user taps "Fermer" (clears the router's route).
    let onClose: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            destination
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer") { onClose() }
                    }
                }
        }
    }

    // MARK: - Route → view

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .seance(let uuid):
            if let seance = fetchSeance(uuid) {
                SeanceDetailView(seance: seance)
            } else {
                NotFoundView(message: "Séance introuvable")
            }
        case .seanceFinish(let uuid):
            if let seance = fetchSeance(uuid) {
                SeanceDetailView(seance: seance, autoFinish: true)
            } else {
                NotFoundView(message: "Séance introuvable")
            }
        case .client(let uuid):
            if let client = fetchClient(uuid) {
                ClientDetailView(client: client)
            } else {
                NotFoundView(message: "Client introuvable")
            }
        case .compta:
            ComptabiliteView()
        }
    }

    // MARK: - Fetching by stable uuid

    /// Fetches the session whose stable `uuid` matches the deep link, or `nil`.
    private func fetchSeance(_ uuid: UUID) -> Seance? {
        var descriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Fetches the client whose stable `uuid` matches the deep link, or `nil`.
    private func fetchClient(_ uuid: UUID) -> Client? {
        var descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Not-found placeholder

/// Shown when a deep link points at a session/client that no longer exists.
private struct NotFoundView: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
