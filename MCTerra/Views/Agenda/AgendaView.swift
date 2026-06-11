//
//  AgendaView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit
import LocalAuthentication

/// The two display modes of the agenda.
private enum AgendaMode: String, CaseIterable, Identifiable {
    case month
    case day

    var id: String { rawValue }
}

/// Local agenda (Google Agenda style, no sync yet). Shows existing sessions
/// in a month grid or a day list. Google Calendar sync will come later.
struct AgendaView: View {
    /// All stored sessions, oldest first (we group/sort per day ourselves).
    @Query(sort: \Seance.date, order: .forward) private var seances: [Seance]

    @State private var mode: AgendaMode = .month
    /// The day currently focused (defaults to today).
    @State private var selectedDate: Date = .now
    /// The month currently shown in the grid (any date within that month).
    @State private var visibleMonth: Date = .now
    /// Drives the standalone "Nouvelle séance" sheet (client picked or typed).
    @State private var showNewSeance = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            content
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewSeance = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewSeance) {
            NewSeanceView()
        }
    }

    // MARK: - Mode switcher

    @ViewBuilder
    private var modePicker: some View {
        Picker("Affichage", selection: $mode) {
            Text("Mois").tag(AgendaMode.month)
            Text("Jour").tag(AgendaMode.day)
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .month:
            MonthGridView(
                visibleMonth: $visibleMonth,
                selectedDate: $selectedDate,
                seancesByDay: seancesByDay,
                onSelectDay: { day in
                    selectedDate = day
                    mode = .day
                }
            )
        case .day:
            DayListView(
                selectedDate: $selectedDate,
                seances: seancesOn(selectedDate)
            )
        }
    }

    // MARK: - Data helpers

    /// Sessions grouped by their day-start date, each group sorted by time.
    /// Used by the month grid to draw the per-day event pills.
    private var seancesByDay: [Date: [Seance]] {
        var grouped: [Date: [Seance]] = [:]
        for seance in seances {
            let key = calendar.startOfDay(for: seance.date)
            grouped[key, default: []].append(seance)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.date < $1.date }
        }
        return grouped
    }

    /// Sessions happening on the given day, sorted by time.
    private func seancesOn(_ day: Date) -> [Seance] {
        seances
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Event color

/// Google-Calendar-style coloring: each event gets a stable color derived from
/// its display name, so the same client keeps the same color across the grid.
/// The palette stays on-brand (turquoise/violet leaning) and readable.
enum SeanceColor {
    /// On-brand palette used to tint the event pills/dots.
    private static let palette: [Color] = [
        Color(red: 0.10, green: 0.65, blue: 0.62), // turquoise (brand)
        Color(red: 0.45, green: 0.35, blue: 0.80), // violet (brand)
        Color(red: 0.20, green: 0.55, blue: 0.85), // blue
        Color(red: 0.85, green: 0.45, blue: 0.55), // rose
        Color(red: 0.90, green: 0.60, blue: 0.25), // amber
        Color(red: 0.30, green: 0.65, blue: 0.45)  // green
    ]

    /// A stable color for the given session, hashed from client/service name.
    static func color(for seance: Seance) -> Color {
        let key = seance.client?.name ?? seance.serviceName
        // Deterministic, non-negative bucket from the string's unicode scalars.
        var hash = 5381
        for scalar in key.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        let index = abs(hash) % palette.count
        return palette[index]
    }

    /// The label shown on a pill/row: client name if any, else the service name.
    static func label(for seance: Seance) -> String {
        seance.client?.name ?? seance.serviceName
    }
}

// MARK: - Month grid

/// A month calendar grid (7 columns, leading/trailing days padded to fill
/// complete weeks). Each day cell shows its sessions as stacked colored pills,
/// Google-Calendar style.
private struct MonthGridView: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    /// Sessions grouped by day-start date, each group sorted by time.
    let seancesByDay: [Date: [Seance]]
    /// Called when a day cell is tapped.
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            daysGrid
            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: Header (month label + prev/next)

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.primary)
    }

    /// Localized weekday symbols, reordered to the calendar's first weekday.
    private var weekdayHeader: some View {
        HStack {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(verbatim: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDays) { gridDay in
                DayCell(
                    gridDay: gridDay,
                    isSelected: isSelected(gridDay),
                    isToday: isToday(gridDay),
                    seances: seances(for: gridDay)
                )
                .onTapGesture {
                    if let date = gridDay.date {
                        onSelectDay(date)
                    }
                }
            }
        }
    }

    // MARK: Computations

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    /// Short weekday symbols, rotated so index 0 is the calendar's first weekday.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1 // firstWeekday is 1-based
        return Array(symbols[first...] + symbols[..<first])
    }

    /// All cells of the grid: leading blanks, the month's days, trailing blanks
    /// to complete the last week.
    private var gridDays: [GridDay] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth)
        else {
            return []
        }

        let firstOfMonth = monthInterval.start
        // How many blank cells before the 1st (offset from the first weekday).
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [GridDay] = []
        for _ in 0..<leadingBlanks {
            cells.append(GridDay(date: nil))
        }
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(GridDay(date: date))
            }
        }
        // Pad to a full final week (multiple of 7).
        let remainder = cells.count % 7
        if remainder != 0 {
            for _ in 0..<(7 - remainder) {
                cells.append(GridDay(date: nil))
            }
        }
        return cells
    }

    /// Sessions for the given grid day (empty for padding cells), sorted by time.
    private func seances(for gridDay: GridDay) -> [Seance] {
        guard let date = gridDay.date else { return [] }
        return seancesByDay[calendar.startOfDay(for: date)] ?? []
    }

    private func isSelected(_ gridDay: GridDay) -> Bool {
        guard let date = gridDay.date else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ gridDay: GridDay) -> Bool {
        guard let date = gridDay.date else { return false }
        return calendar.isDateInToday(date)
    }

    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            visibleMonth = newMonth
        }
    }
}

/// One cell in the month grid (either a real day or an empty padding slot).
private struct GridDay: Identifiable {
    let id = UUID()
    /// `nil` for padding cells outside the current month.
    let date: Date?
}

/// A single day cell: the day number, then up to `maxVisible` colored event
/// pills (Google-Calendar style) and a "+N" overflow marker for the rest.
private struct DayCell: View {
    let gridDay: GridDay
    let isSelected: Bool
    let isToday: Bool
    /// Sessions on this day, sorted by time. Empty for padding cells.
    let seances: [Seance]

    private let calendar = Calendar.current
    /// How many event pills fit before we collapse the rest into "+N".
    private let maxVisible = 3
    /// Fixed cell height so all weeks line up regardless of event count.
    private let cellHeight: CGFloat = 92

    var body: some View {
        if let date = gridDay.date {
            dayContent(date)
        } else {
            // Empty padding cell keeps the grid aligned.
            Color.clear.frame(height: cellHeight)
        }
    }

    @ViewBuilder
    private func dayContent(_ date: Date) -> some View {
        VStack(spacing: 3) {
            dayNumberBadge(date)
            pills
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    private func dayNumberBadge(_ date: Date) -> some View {
        Text(verbatim: dayNumber(date))
            .font(.caption)
            .fontWeight(isToday ? .bold : .regular)
            .foregroundStyle(numberColor)
            .frame(width: 24, height: 24)
            .background(selectionBackground)
    }

    /// The stacked event pills, clamped to `maxVisible` plus an overflow marker.
    @ViewBuilder
    private var pills: some View {
        VStack(spacing: 2) {
            ForEach(seances.prefix(maxVisible)) { seance in
                EventPill(seance: seance)
            }
            if seances.count > maxVisible {
                Text(verbatim: "+\(seances.count - maxVisible)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
            }
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            Circle().fill(.tint)
        } else if isToday {
            Circle().fill(.tint.opacity(0.18))
        }
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    private func dayNumber(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }
}

/// A small colored bar inside a month cell showing one event's name, Google
/// Calendar style: a tinted rounded background with the truncated label.
private struct EventPill: View {
    let seance: Seance

    var body: some View {
        Text(verbatim: SeanceColor.label(for: seance))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SeanceColor.color(for: seance))
            )
    }
}

// MARK: - Day list

/// The list of sessions for the selected day, sorted by time, with a header
/// to step through days.
private struct DayListView: View {
    @Environment(\.modelContext) private var context
    /// Connexion Google partagée, pour supprimer aussi l'event lié au swipe-delete.
    @EnvironmentObject private var google: GoogleCalendarService
    /// Calendrier choisi dans les Réglages, "" quand aucun/déconnecté.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""
    @Binding var selectedDate: Date
    /// Sessions on `selectedDate`, already sorted by time.
    let seances: [Seance]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            list
        }
    }

    private var dayHeader: some View {
        HStack {
            Button { changeDay(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(dayTitle)
                .font(.headline)
            Spacer()
            Button { changeDay(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var list: some View {
        if seances.isEmpty {
            ContentUnavailableView {
                Label("Aucune séance", systemImage: "calendar.badge.clock")
            } description: {
                Text("Pas de séance prévue ce jour.")
            }
        } else {
            List {
                ForEach(seances) { seance in
                    AgendaSeanceLink(seance: seance)
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
        }
    }

    /// Swipe-to-delete a session straight from the day list, gated behind
    /// Face ID / device passcode (fail-open if the device has neither).
    private func delete(_ offsets: IndexSet) {
        // Capture the targets now, before the async auth callback runs.
        let targets = offsets.map { seances[$0] }
        authenticate {
            for seance in targets {
                // Supprime l'event Google lié (best-effort) : on capture eventId +
                // calendarId AVANT le context.delete, comme SeanceDetailView.deleteSeance().
                let eventId = seance.googleEventId
                let calendarId = googleCalendarId
                if google.isSignedIn, !calendarId.isEmpty, !eventId.isEmpty {
                    Task { await google.deleteEvent(calendarId: calendarId, eventId: eventId) }
                }
                NotificationService.cancel(for: seance)
                context.delete(seance)
            }
            WidgetCenter.shared.reloadAllTimelines()
            // Resync la liste push après suppression (sinon timer pour séance morte).
            PushToStartService.shared.sync(using: context)
        }
    }

    /// Confirms the deletion with Face ID / device passcode before running
    /// `onSuccess`. Falls back to running it directly when no authentication
    /// is available on the device.
    private func authenticate(onSuccess: @escaping () -> Void) {
        let laContext = LAContext()
        var error: NSError?
        let reason = String(localized: "Confirme la suppression de la séance")
        if laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                if success { Task { @MainActor in onSuccess() } }
            }
        } else {
            onSuccess()
        }
    }

    private var dayTitle: String {
        selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private func changeDay(by value: Int) {
        if let newDay = calendar.date(byAdding: .day, value: value, to: selectedDate) {
            selectedDate = newDay
        }
    }
}

/// A tappable session row. Pushes the dedicated session detail screen, where all
/// the session's actions (start/finish, edit, delete, summary) live one tap away.
private struct AgendaSeanceLink: View {
    let seance: Seance

    var body: some View {
        NavigationLink {
            SeanceDetailView(seance: seance)
        } label: {
            AgendaSeanceRow(seance: seance)
        }
    }
}

/// Visual content of a session row: time, client, service, duration.
private struct AgendaSeanceRow: View {
    let seance: Seance

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

    /// Round colored marker matching the event's color in the month grid.
    private var colorDot: some View {
        Circle()
            .fill(SeanceColor.color(for: seance))
            .frame(width: 10, height: 10)
    }

    private var timeBlock: some View {
        Text(seance.date, format: .dateTime.hour().minute())
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(.tint)
            .frame(width: 52, alignment: .leading)
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
    NavigationStack { AgendaView() }
        .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
