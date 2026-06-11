//
//  SeancesDuJourView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import SwiftUI
import SwiftData

/// Accès direct aux séances du jour (raccourci depuis le menu).
///
/// Avant, voir une séance demandait 4 taps (Menu → Clients → personne → séance,
/// ou Menu → Agenda → jour → séance). Cette vue liste directement les séances
/// d'aujourd'hui, triées par heure, et affiche aussi la prochaine séance à venir
/// quand la journée est vide. Chaque ligne pousse le détail (`SeanceDetailView`),
/// dans le même style que la liste de l'agenda.
struct SeancesDuJourView: View {
    /// Toutes les séances, plus ancienne d'abord (on filtre/trie nous-mêmes).
    @Query(sort: \Seance.date, order: .forward) private var seances: [Seance]

    private let calendar = Calendar.current

    var body: some View {
        content
            .navigationTitle("Séances du jour")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if seancesAujourdhui.isEmpty {
            emptyState
        } else {
            List {
                Section(dateDuJour) {
                    ForEach(seancesAujourdhui) { seance in
                        SeanceDuJourLink(seance: seance)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Quand la journée est vide : message clair, plus la prochaine séance à venir
    /// (s'il y en a une) pour garder un point d'accès rapide.
    @ViewBuilder
    private var emptyState: some View {
        if let prochaine = prochaineSeance {
            List {
                Section("Prochaine séance") {
                    SeanceDuJourLink(seance: prochaine, showDay: true)
                }
            }
            .listStyle(.insetGrouped)
            .overlay(alignment: .top) {
                Text("Aucune séance aujourd'hui")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        } else {
            ContentUnavailableView {
                Label("Aucune séance aujourd'hui", systemImage: "sun.max")
            } description: {
                Text("Pas de séance prévue pour aujourd'hui ni à venir.")
            }
        }
    }

    // MARK: - Données

    /// Les séances d'aujourd'hui (planifiées et terminées), triées par heure.
    private var seancesAujourdhui: [Seance] {
        seances
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
    }

    /// La première séance strictement à venir (après maintenant), hors aujourd'hui.
    private var prochaineSeance: Seance? {
        let now = Date.now
        return seances
            .filter { !calendar.isDateInToday($0.date) && $0.date > now }
            .min { $0.date < $1.date }
    }

    private var dateDuJour: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// Une ligne de séance qui pousse le détail (`SeanceDetailView`), comme l'agenda.
private struct SeanceDuJourLink: View {
    let seance: Seance
    /// Affiche aussi le jour (utile pour la prochaine séance hors aujourd'hui).
    var showDay: Bool = false

    var body: some View {
        NavigationLink {
            SeanceDetailView(seance: seance)
        } label: {
            SeanceDuJourRow(seance: seance, showDay: showDay)
        }
    }
}

/// Contenu visuel d'une ligne : heure (et jour optionnel), client, service, durée.
/// Calqué sur `AgendaSeanceRow` pour rester cohérent avec l'agenda.
private struct SeanceDuJourRow: View {
    let seance: Seance
    var showDay: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            colorDot
            timeBlock
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: clientName)
                    .font(.subheadline.weight(.semibold))
                detailLine
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Pastille colorée, même couleur que dans l'agenda.
    private var colorDot: some View {
        Circle()
            .fill(SeanceColor.color(for: seance))
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private var timeBlock: some View {
        if showDay {
            VStack(alignment: .leading, spacing: 2) {
                Text(seance.date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(seance.date, format: .dateTime.hour().minute())
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
            }
            .frame(width: 64, alignment: .leading)
        } else {
            Text(seance.date, format: .dateTime.hour().minute())
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
                .frame(width: 52, alignment: .leading)
        }
    }

    private var detailLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: seance.serviceName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "·")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(seance.durationMinutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var clientName: String {
        seance.client?.name ?? String(localized: "Sans client")
    }
}

#Preview {
    NavigationStack { SeancesDuJourView() }
        .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
