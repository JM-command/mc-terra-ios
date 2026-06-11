//
//  HomeStatsView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// A compact three-card strip shown on the empty home screen: this month's
/// revenue, the number of sessions today, and the next upcoming session.
/// All scoping uses the clinic's Zurich calendar, matching the AI toolbox.
struct HomeStatsView: View {
    /// All sessions, ordered by date. Month/day scoping and the "next" lookup
    /// happen in Swift so the SwiftData predicate stays simple.
    @Query(sort: \Seance.date, order: .forward)
    private var seances: [Seance]

    /// The clinic runs on Zurich time, like the AI toolbox.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return c
    }

    /// Revenue for the current month: finished sessions that were actually paid
    /// (priceCHF > 0), summed.
    private var monthRevenue: Double {
        let now = Date()
        return seances
            .filter { $0.status == SeanceStatus.completed }
            .filter { $0.priceCHF > 0 }
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.priceCHF }
    }

    /// Number of sessions scheduled for today.
    private var todayCount: Int {
        let now = Date()
        return seances.filter { calendar.isDate($0.date, inSameDayAs: now) }.count
    }

    /// The soonest session still in the future, if any.
    private var nextSeance: Seance? {
        let now = Date()
        return seances.first { $0.date >= now }
    }

    var body: some View {
        HStack(spacing: 10) {
            StatCard(
                icon: "francsign.circle",
                title: "Ce mois",
                value: CurrencyFormat.chf(monthRevenue)
            )
            StatCard(
                icon: "calendar",
                title: "Aujourd'hui",
                value: todayCount == 1
                    ? String(localized: "1 séance")
                    : String(localized: "\(todayCount) séances")
            )
            StatCard(
                icon: "clock",
                title: "Prochaine",
                value: nextValue
            )
        }
        .padding(.horizontal, 24)
    }

    /// "Aucune" when there is no upcoming session, otherwise the date and client.
    private var nextValue: String {
        guard let next = nextSeance else {
            return String(localized: "Aucune")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = "d MMM, HH:mm"
        let when = formatter.string(from: next.date)
        if let name = next.client?.name, !name.isEmpty {
            return "\(when)\n\(name)"
        }
        return when
    }
}

/// One small rounded card: an accent icon, a muted title, and the value.
private struct StatCard: View {
    let icon: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

#Preview {
    HomeStatsView()
        .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
