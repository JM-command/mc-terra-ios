//
//  SearchView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// Full-screen search reached from the menu's magnifying glass. Searches across
/// clients (name / phone) and sessions (client name, forfait, note) and lets
/// Marta jump straight to the matching detail screen.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Seance.date, order: .reverse) private var seances: [Seance]

    @State private var query = ""

    var body: some View {
        NavigationStack {
            results
                .navigationTitle("Recherche")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
        }
        .searchable(text: $query, prompt: Text("Client, séance, note..."))
    }

    @ViewBuilder
    private var results: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView {
                Label("Rechercher", systemImage: "magnifyingglass")
            } description: {
                Text("Tape un nom de client, un forfait ou une note.")
            }
        } else if filteredClients.isEmpty, filteredSeances.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if !filteredClients.isEmpty {
                    Section("Clients") {
                        ForEach(filteredClients) { client in
                            NavigationLink {
                                ClientDetailView(client: client)
                            } label: {
                                clientRow(client)
                            }
                        }
                    }
                }
                if !filteredSeances.isEmpty {
                    Section("Séances") {
                        ForEach(filteredSeances) { seance in
                            NavigationLink {
                                SeanceDetailView(seance: seance)
                            } label: {
                                seanceRow(seance)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func clientRow(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: client.name)
            if !client.phone.isEmpty {
                Text(verbatim: client.phone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func seanceRow(_ seance: Seance) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: seance.client?.name ?? String(localized: "Sans client"))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                Text(seance.date, format: .dateTime.day().month().year())
                Text(verbatim: "·")
                Text(verbatim: seance.serviceName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filtering

    private var filteredClients: [Client] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return clients.filter {
            $0.name.lowercased().contains(q) || $0.phone.contains(q)
        }
    }

    private var filteredSeances: [Seance] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return seances.filter { seance in
            (seance.client?.name.lowercased().contains(q) ?? false)
                || seance.serviceName.lowercased().contains(q)
                || seance.note.lowercased().contains(q)
        }
    }
}
