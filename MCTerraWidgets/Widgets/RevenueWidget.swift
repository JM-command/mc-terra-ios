//
//  RevenueWidget.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  "Revenus du mois" widget.
//  - small:  total CHF earned this month (completed sessions).
//  - medium: total + session count + quick breakdown by payment method.
//  - large:  total + list of the latest paid sessions.
//
//  Reads completed sessions for the current calendar month from the shared
//  App Group SwiftData store. French labels are hard-coded (PT pass later).

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// One timeline entry for the revenue widget. Carries pre-computed totals plus
/// the recent completed sessions so the views stay dumb.
struct RevenueEntry: TimelineEntry {
    let date: Date
    /// Total CHF from completed sessions in the current month.
    let total: Double
    /// Number of completed sessions this month.
    let count: Int
    /// CHF totals keyed by payment method raw value ("twint"/"carte"/"cash"/"").
    let byMethod: [String: Double]
    /// Most recent completed sessions this month, newest first.
    let recent: [SessionSnapshot]
}

// MARK: - Provider

/// Builds the revenue timeline from completed sessions in the current month.
struct RevenueProvider: TimelineProvider {
    func placeholder(in context: Context) -> RevenueEntry {
        RevenueEntry.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (RevenueEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RevenueEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh on the standard cadence, but never later than the start of next
        // month so the total resets cleanly.
        let next = min(WidgetRefresh.next(), startOfNextMonth())
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Reads completed sessions for the current month and aggregates them.
    private func loadEntry() -> RevenueEntry {
        guard let context = WidgetStore.context() else {
            return RevenueEntry(date: .now, total: 0, count: 0, byMethod: [:], recent: [])
        }

        let (monthStart, monthEnd) = monthBounds()
        let completed = SeanceStatus.completed

        var descriptor = FetchDescriptor<Seance>(
            predicate: #Predicate {
                $0.status == completed && $0.date >= monthStart && $0.date < monthEnd
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        let sessions = (try? context.fetch(descriptor))?.map { $0.snapshot() } ?? []
        let total = sessions.reduce(0) { $0 + $1.priceCHF }
        var byMethod: [String: Double] = [:]
        for s in sessions {
            byMethod[s.paymentMethod, default: 0] += s.priceCHF
        }

        return RevenueEntry(
            date: .now,
            total: total,
            count: sessions.count,
            byMethod: byMethod,
            recent: Array(sessions.prefix(6))
        )
    }

    private func monthBounds() -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? .now
        return (start, end)
    }

    private func startOfNextMonth() -> Date {
        monthBounds().1
    }
}

// MARK: - Widget declaration

struct RevenueWidget: Widget {
    let kind = "revenue"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RevenueProvider()) { entry in
            RevenueView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color("AccentColor"))
        }
        .configurationDisplayName("Revenus du mois")
        .description("Total encaissé ce mois et dernières séances payées.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view (routes per family)

struct RevenueView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RevenueEntry

    var body: some View {
        content
            // The whole revenue widget (all sizes) deep-links to the accounting
            // dashboard: `mcterra://compta`.
            .widgetURL(WidgetDeepLink.compta)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            RevenueSmall(entry: entry)
        case .systemLarge:
            RevenueLarge(entry: entry)
        default:
            RevenueMedium(entry: entry)
        }
    }
}

// MARK: - Sample data (placeholder / preview)

extension RevenueEntry {
    static let sample = RevenueEntry(
        date: .now,
        total: 1840,
        count: 16,
        byMethod: ["twint": 920, "carte": 640, "cash": 280],
        recent: [
            SessionSnapshot(id: "1", date: .now.addingTimeInterval(-3600 * 2), clientName: "Marta Coelho",
                            serviceName: "Thérapie Émotionnelle", durationMinutes: 60, priceCHF: 120,
                            location: "cabinet", paymentMethod: "twint"),
            SessionSnapshot(id: "2", date: .now.addingTimeInterval(-3600 * 28), clientName: "Léa Dubois",
                            serviceName: "Coaching", durationMinutes: 45, priceCHF: 90,
                            location: "zoom", paymentMethod: "carte"),
            SessionSnapshot(id: "3", date: .now.addingTimeInterval(-3600 * 52), clientName: "Paulo Santos",
                            serviceName: "Suivi", durationMinutes: 60, priceCHF: 110,
                            location: "cabinet", paymentMethod: "cash")
        ]
    )
}

#Preview("Small", as: .systemSmall) {
    RevenueWidget()
} timeline: {
    RevenueEntry.sample
}

#Preview("Medium", as: .systemMedium) {
    RevenueWidget()
} timeline: {
    RevenueEntry.sample
}

#Preview("Large", as: .systemLarge) {
    RevenueWidget()
} timeline: {
    RevenueEntry.sample
}
