//
//  ClientsListView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit
import LocalAuthentication

/// Dedicated screen listing all clients.
struct ClientsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var showNewClient = false

    var body: some View {
        List {
            if clients.isEmpty {
                ContentUnavailableView {
                    Label("Aucun client", systemImage: "person.2")
                } description: {
                    Text("Ajoute ton premier client.")
                }
            } else {
                ForEach(clients) { client in
                    NavigationLink {
                        ClientDetailView(client: client)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: client.name)
                            if !client.phone.isEmpty {
                                Text(verbatim: client.phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewClient = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewClient) {
            NewClientView()
        }
    }

    /// Swipe-to-delete a client. Guarded by Face ID / passcode so an accidental
    /// swipe can't wipe a client (and its sessions, via the cascade rule).
    private func delete(_ offsets: IndexSet) {
        let targets = offsets.map { clients[$0] }
        authenticate {
            for client in targets {
                context.delete(client)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Asks for Face ID / passcode, then runs `onSuccess`. Fails open when the
    /// device has no biometrics nor passcode set, so deletion still works there.
    private func authenticate(onSuccess: @escaping () -> Void) {
        let context = LAContext()
        var error: NSError?
        let reason = String(localized: "Confirme la suppression du client")
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                if success {
                    Task { @MainActor in onSuccess() }
                }
            }
        } else {
            onSuccess()
        }
    }
}
