//
//  DailyReminderService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules smart recurring local notifications that summarize upcoming work,
/// independent of the per-session reminders handled by `NotificationService`.
///
/// Each reminder uses a fixed identifier so re-running these methods replaces the
/// previous request instead of stacking duplicates. All methods are safe to call
/// regardless of the authorization state: the system drops requests when
/// permission is missing.
enum DailyReminderService {

    /// The clinic runs on Zurich time, so all day boundaries and fire times are
    /// computed in that timezone rather than the device locale.
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return c
    }

    // MARK: - Identifiers

    /// Fixed identifier for the daily "tomorrow summary" reminder.
    private static let summaryIdentifier = "daily-summary"
    /// Fixed identifier for the weekly stale-clients nudge.
    private static let staleClientsIdentifier = "stale-clients"

    // MARK: - Tomorrow summary

    /// Builds a one-shot reminder firing today at 19:00 (Zurich) that announces the
    /// number of planned sessions tomorrow, plus the first one's time and client.
    /// Any previous summary is cancelled first; nothing is scheduled when tomorrow
    /// has no planned session.
    static func scheduleTomorrowSummary(using context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        // Always clear the previous summary so it never lingers or stacks.
        center.removePendingNotificationRequests(withIdentifiers: [summaryIdentifier])

        let cal = calendar
        let startOfTomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
        guard let startOfDayAfter = cal.date(byAdding: .day, value: 1, to: startOfTomorrow) else { return }

        // Planned (not finished) sessions happening tomorrow, earliest first.
        let completed = SeanceStatus.completed
        let descriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { seance in
                seance.date >= startOfTomorrow
                    && seance.date < startOfDayAfter
                    && seance.status != completed
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else { return }

        // Fire today at 19:00 Zurich time; skip if that moment already passed.
        guard let fireDate = cal.date(
            bySettingHour: 19, minute: 0, second: 0, of: .now
        ), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "MC-TERRA")
        content.body = summaryBody(for: sessions, calendar: cal)
        content.sound = .default
        // Taper le résumé ouvre directement la première séance du lendemain.
        if let first = sessions.first {
            content.userInfo = ["deepLink": "mcterra://seance/\(first.uuid.uuidString)"]
        }

        let components = cal.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: summaryIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Body line e.g. "Demain : 3 séances, première à 9h00 avec Sophie." with the
    /// count pluralized and the first session's time and client filled in.
    private static func summaryBody(for sessions: [Seance], calendar cal: Calendar) -> String {
        let count = sessions.count
        let countText = count == 1
            ? String(localized: "1 séance")
            : String(localized: "\(count) séances")

        guard let first = sessions.first else {
            return String(localized: "Demain : \(countText).")
        }

        var timeFormatter = DateFormatter()
        timeFormatter.calendar = cal
        timeFormatter.timeZone = cal.timeZone
        // "9h00" style, matching the French wording used in the body.
        timeFormatter.dateFormat = "H'h'mm"
        let time = timeFormatter.string(from: first.date)

        if let clientName = first.client?.name, !clientName.isEmpty {
            return String(localized: "Demain : \(countText), première à \(time) avec \(clientName).")
        }
        return String(localized: "Demain : \(countText), première à \(time).")
    }

    // MARK: - Stale clients nudge

    /// Builds a weekly reminder (Sunday 18:00 Zurich) when one or more clients have
    /// had no session in the last six weeks. Any previous nudge is cancelled first;
    /// nothing is scheduled when every client is recent.
    static func scheduleStaleClientsNudge(using context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        // Always clear the previous nudge so it never lingers or stacks.
        center.removePendingNotificationRequests(withIdentifiers: [staleClientsIdentifier])

        let cal = calendar
        guard let cutoff = cal.date(byAdding: .weekOfYear, value: -6, to: .now) else { return }

        guard let clients = try? context.fetch(FetchDescriptor<Client>()) else { return }
        // A client is stale when none of their sessions happened after the cutoff.
        let staleCount = clients.filter { client in
            !client.seances.contains { $0.date >= cutoff }
        }.count
        guard staleCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "MC-TERRA")
        content.body = staleClientsBody(count: staleCount)
        content.sound = .default

        // Weekday 1 == Sunday in the Gregorian calendar; repeats every week.
        var components = DateComponents()
        components.weekday = 1
        components.hour = 18
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: staleClientsIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Body line e.g. "Tu as 2 client(s) pas vu(s) depuis plus de 6 semaines.".
    private static func staleClientsBody(count: Int) -> String {
        count == 1
            ? String(localized: "Tu as 1 client pas vu depuis plus de 6 semaines.")
            : String(localized: "Tu as \(count) clients pas vus depuis plus de 6 semaines.")
    }
}
