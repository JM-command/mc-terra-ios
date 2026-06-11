//
//  RecentClientsWidget.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  "Clients récents" widget.
//  - small:  the most recent client (name + session count).
//  - medium: the latest 3 clients as a compact list.
//  - large:  the latest 6 clients with session counts.
//
//  Reads the same SwiftData store as the app through the App Group container.
//  Each client row deep-links to `mcterra://client/<uuid>`. French labels are
//  hard-coded on purpose (PT pass comes later); they are NOT routed through
//  Localizable.xcstrings.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// One timeline entry for the recent-clients widget.
struct RecentClientsEntry: TimelineEntry {
    let date: Date
    /// Most recently added clients, newest first (falls back to name order when
    /// `createdAt` ties). Carries lightweight snapshots so the views stay dumb.
    let clients: [ClientSnapshot]
}

// MARK: - Provider

/// Builds the recent-clients timeline by reading clients from the App Group store.
struct RecentClientsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentClientsEntry {
        RecentClientsEntry(date: .now, clients: RecentClientsEntry.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentClientsEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentClientsEntry>) -> Void) {
        let entry = loadEntry()
        completion(Timeline(entries: [entry], policy: .after(WidgetRefresh.next())))
    }

    /// Reads the most recently created clients from SwiftData.
    private func loadEntry() -> RecentClientsEntry {
        guard let context = WidgetStore.context() else {
            return RecentClientsEntry(date: .now, clients: [])
        }

        // Sort by creation date descending; SwiftData breaks ties deterministically,
        // and we add a name fallback in-memory for clients sharing a timestamp.
        var descriptor = FetchDescriptor<Client>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.name, order: .forward)
            ]
        )
        descriptor.fetchLimit = 6

        let clients = (try? context.fetch(descriptor))?.map { $0.clientSnapshot() } ?? []
        return RecentClientsEntry(date: .now, clients: clients)
    }
}

// MARK: - Widget declaration

struct RecentClientsWidget: Widget {
    let kind = "recent-clients"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentClientsProvider()) { entry in
            RecentClientsView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color("AccentColor"))
        }
        .configurationDisplayName("Clients récents")
        .description("Vos derniers clients ajoutés, un tap pour ouvrir leur fiche.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view (routes per family)

/// Picks the layout for the current widget size. Each size is its own small
/// view to keep the type-checker fast.
struct RecentClientsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentClientsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            // Small has one tap target: deep-link the whole widget to the most
            // recent client. Medium/large make each row its own `Link`.
            RecentClientsSmall(client: entry.clients.first)
                .widgetURL(entry.clients.first.flatMap { WidgetDeepLink.client($0.id) })
        case .systemLarge:
            RecentClientsList(clients: entry.clients, limit: 6)
        default:
            RecentClientsList(clients: entry.clients, limit: 3)
        }
    }
}

// MARK: - Sample data (placeholder / preview)

extension RecentClientsEntry {
    static let sample: [ClientSnapshot] = [
        ClientSnapshot(id: "1", name: "Marta Coelho", language: "pt",
                       createdAt: .now.addingTimeInterval(-3600), seanceCount: 8),
        ClientSnapshot(id: "2", name: "Léa Dubois", language: "fr",
                       createdAt: .now.addingTimeInterval(-3600 * 30), seanceCount: 3),
        ClientSnapshot(id: "3", name: "Paulo Santos", language: "pt",
                       createdAt: .now.addingTimeInterval(-3600 * 60), seanceCount: 1)
    ]
}

#Preview("Small", as: .systemSmall) {
    RecentClientsWidget()
} timeline: {
    RecentClientsEntry(date: .now, clients: RecentClientsEntry.sample)
}

#Preview("Medium", as: .systemMedium) {
    RecentClientsWidget()
} timeline: {
    RecentClientsEntry(date: .now, clients: RecentClientsEntry.sample)
}

#Preview("Large", as: .systemLarge) {
    RecentClientsWidget()
} timeline: {
    RecentClientsEntry(date: .now, clients: RecentClientsEntry.sample)
}
