//
//  MenuView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// Full-screen menu page (reached by swiping right from the home).
/// Title + search + settings on top, then plain navigation rows that
/// push dedicated views (no more collapsible folders — keep it simple).
struct MenuView: View {
    /// Called to slide back to the home (command) page.
    var goHome: () -> Void

    @State private var showSettings = false
    @State private var showNewClient = false
    @State private var showContactPicker = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar

                List {
                    Button {
                        showNewClient = true
                    } label: {
                        Label("Nouveau client", systemImage: "person.badge.plus")
                            .foregroundStyle(.tint)
                    }

                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Importer contacts", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.tint)
                    }

                    NavigationLink(value: MenuRoute.today) {
                        Label("Séances du jour", systemImage: "sun.max")
                    }
                    .spotlightTarget("today")
                    NavigationLink(value: MenuRoute.clients) {
                        Label("Clients", systemImage: "person.2")
                    }
                    .spotlightTarget("clients")
                    NavigationLink(value: MenuRoute.agenda) {
                        Label("Agenda", systemImage: "calendar")
                    }
                    .spotlightTarget("agenda")
                    NavigationLink(value: MenuRoute.accounting) {
                        Label("Comptabilité", systemImage: "chart.bar")
                    }
                    .spotlightTarget("compta")
                }
                .listStyle(.plain)
            }
            // Floating "Accueil" button, only on the menu root.
            .overlay(alignment: .bottomTrailing) {
                homeButton.padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MenuRoute.self) { route in
                switch route {
                case .today: SeancesDuJourView()
                case .clients: ClientsListView()
                case .agenda: AgendaView()
                case .accounting: ComptabiliteView()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showNewClient) {
            NewClientView()
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerView()
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }

    // MARK: - Top bar (title left, search + settings right)

    private var topBar: some View {
        HStack {
            Text(verbatim: "MC-TERRA")
                .font(.largeTitle.bold())

            Spacer()

            HStack(spacing: 2) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .padding(8)
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .padding(8)
                }
            }
            .foregroundStyle(.primary)
            .background(Capsule().fill(Color.gray.opacity(0.15)))
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Floating "Home" button (back to the command screen)

    private var homeButton: some View {
        Button {
            goHome()
        } label: {
            Label("Accueil", systemImage: "house")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(.regularMaterial))
                .shadow(radius: 8, y: 4)
        }
        .foregroundStyle(.primary)
    }
}

/// The destinations reachable from the menu.
enum MenuRoute: Hashable {
    case today
    case clients
    case agenda
    case accounting
}

#Preview {
    MenuView(goHome: {})
}
