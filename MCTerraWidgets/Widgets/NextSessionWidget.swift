//
//  NextSessionWidget.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  "Prochaine séance / Agenda" widget.
//  - small:  the next upcoming session (client, time, location icon).
//  - medium: today's sessions (list).
//  - large:  the next 5-6 upcoming sessions with date/time/client/service.
//
//  Reads the same SwiftData store as the app through the App Group container.
//  French labels are hard-coded on purpose (PT pass comes later); they are NOT
//  routed through Localizable.xcstrings.

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// One timeline entry for the agenda widget.
struct NextSessionEntry: TimelineEntry {
    let date: Date
    /// Today's sessions (planned + completed), sorted by time. Used by medium.
    let today: [SessionSnapshot]
    /// Upcoming planned sessions from now on, sorted ascending. Used by small/large.
    let upcoming: [SessionSnapshot]
}

// MARK: - Provider

/// Builds the agenda timeline by reading sessions from the App Group store.
struct NextSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextSessionEntry {
        NextSessionEntry(date: .now, today: NextSessionEntry.sample, upcoming: NextSessionEntry.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextSessionEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextSessionEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh on a fixed cadence; the system also reloads at the day boundary
        // for us when we request a date in the future.
        let next = min(WidgetRefresh.next(), startOfNextDay())
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Reads today's and upcoming sessions from SwiftData.
    private func loadEntry() -> NextSessionEntry {
        guard let context = WidgetStore.context() else {
            return NextSessionEntry(date: .now, today: [], upcoming: [])
        }

        let now = Date.now
        let dayStart = Calendar.current.startOfDay(for: now)
        let dayEnd = startOfNextDay()
        let planned = SeanceStatus.planned

        // Today's sessions (any status), sorted by time ascending.
        var todayDescriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        todayDescriptor.fetchLimit = 12

        // Upcoming planned sessions from now on, soonest first.
        var upcomingDescriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { $0.date >= now && $0.status == planned },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        upcomingDescriptor.fetchLimit = 6

        let today = (try? context.fetch(todayDescriptor))?.map { $0.snapshot() } ?? []
        let upcoming = (try? context.fetch(upcomingDescriptor))?.map { $0.snapshot() } ?? []
        return NextSessionEntry(date: now, today: today, upcoming: upcoming)
    }

    private func startOfNextDay() -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
    }
}

// MARK: - Widget declaration

struct NextSessionWidget: Widget {
    let kind = "next-session"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextSessionProvider()) { entry in
            NextSessionView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color("AccentColor"))
        }
        .configurationDisplayName("Prochaine séance")
        .description("Votre prochaine séance et l'agenda du jour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view (routes per family)

/// Picks the layout for the current widget size. Each size is its own small
/// view to keep the type-checker fast.
struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextSessionEntry

    var body: some View {
        switch family {
        case .systemSmall:
            // Small has a single tap target, so the whole widget deep-links to the
            // next session via `widgetURL`. Medium/large make each row its own
            // `Link` instead (see the row views).
            NextSessionSmall(next: entry.upcoming.first)
                .widgetURL(entry.upcoming.first.flatMap { WidgetDeepLink.seance($0.id) })
        case .systemLarge:
            NextSessionLarge(sessions: entry.upcoming)
        default:
            NextSessionMedium(today: entry.today, fallback: entry.upcoming.first)
        }
    }
}

// MARK: - Sample data (placeholder / preview)

extension NextSessionEntry {
    static let sample: [SessionSnapshot] = [
        SessionSnapshot(id: "1", date: .now.addingTimeInterval(3600), clientName: "Marta Coelho",
                        serviceName: "Thérapie Émotionnelle", durationMinutes: 60, priceCHF: 120,
                        location: "cabinet", paymentMethod: ""),
        SessionSnapshot(id: "2", date: .now.addingTimeInterval(3600 * 4), clientName: "Léa Dubois",
                        serviceName: "Coaching", durationMinutes: 45, priceCHF: 90,
                        location: "zoom", paymentMethod: ""),
        SessionSnapshot(id: "3", date: .now.addingTimeInterval(3600 * 26), clientName: "Paulo Santos",
                        serviceName: "Suivi", durationMinutes: 60, priceCHF: 110,
                        location: "cabinet", paymentMethod: "")
    ]
}

#Preview("Small", as: .systemSmall) {
    NextSessionWidget()
} timeline: {
    NextSessionEntry(date: .now, today: NextSessionEntry.sample, upcoming: NextSessionEntry.sample)
}

#Preview("Medium", as: .systemMedium) {
    NextSessionWidget()
} timeline: {
    NextSessionEntry(date: .now, today: NextSessionEntry.sample, upcoming: NextSessionEntry.sample)
}

#Preview("Large", as: .systemLarge) {
    NextSessionWidget()
} timeline: {
    NextSessionEntry(date: .now, today: NextSessionEntry.sample, upcoming: NextSessionEntry.sample)
}
