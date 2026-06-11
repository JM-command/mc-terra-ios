//
//  NotificationService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules a local "get ready" notification 5 minutes before a planned session.
///
/// Notifications are keyed by the session's stable identifier so they can be
/// cancelled or rescheduled when the session is edited or deleted. All methods
/// are safe to call regardless of the authorization state — the system simply
/// drops requests when permission is missing.
enum NotificationService {

    /// How long before the session the "get ready" reminder fires.
    private static let leadTime: TimeInterval = 5 * 60
    /// How long after the start the "did you forget to start it?" nudge fires.
    private static let nudgeDelay: TimeInterval = 5 * 60

    // MARK: - Authorization

    /// Asks the user for notification permission. Safe to call repeatedly.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in
            // Result intentionally ignored: scheduling no-ops without permission.
        }
    }

    // MARK: - Categories

    /// Enregistre la catégorie "SEANCE_REMINDER" et ses deux boutons d'action.
    /// Appelée au lancement (depuis l'`AppDelegate`) pour que les notifs posées par
    /// `scheduleOne` affichent les actions "Voir la séance" et "Démarrer".
    static func setupCategories() {
        let voir = UNNotificationAction(
            identifier: "VOIR_SEANCE",
            title: String(localized: "Voir la séance"),
            options: [.foreground]
        )
        let demarrer = UNNotificationAction(
            identifier: "DEMARRER_SEANCE",
            title: String(localized: "Démarrer"),
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "SEANCE_REMINDER",
            actions: [voir, demarrer],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Identifier

    /// Identifiant stable par séance, basé sur l'`uuid` de la séance (et non sur
    /// `persistentModelID.hashValue`, dont la valeur peut changer entre deux
    /// lancements, ce qui empêchait `cancel(for:)` de retrouver les notifs posées).
    static func identifier(for seance: Seance) -> String {
        "seance-\(seance.uuid.uuidString)"
    }

    /// All notification ids a session can have (legacy bare id + the three slots).
    private static func allIdentifiers(for seance: Seance) -> [String] {
        let base = identifier(for: seance)
        return [base, base + "-before", base + "-start", base + "-nudge"]
    }

    // MARK: - Schedule

    /// Schedules up to three reminders for a planned session: 5 min before, at the
    /// start time, and a 5-min-after nudge (in case she forgot to start the timer,
    /// since iOS can't start the Live Activity on its own). Replaces any existing.
    static func schedule(for seance: Seance) {
        cancel(for: seance)
        let body = reminderBody(for: seance)
        let base = identifier(for: seance)
        let uuid = seance.uuid.uuidString

        scheduleOne(id: base + "-before",
                    at: seance.date.addingTimeInterval(-leadTime),
                    title: String(localized: "Séance dans 5 minutes"),
                    body: body,
                    seanceUUID: uuid)
        scheduleOne(id: base + "-start",
                    at: seance.date,
                    title: String(localized: "Ta séance commence"),
                    body: body,
                    seanceUUID: uuid)
        scheduleOne(id: base + "-nudge",
                    at: seance.date.addingTimeInterval(nudgeDelay),
                    title: String(localized: "Chrono pas lancé ?"),
                    body: String(localized: "Si la séance a commencé, ouvre l'app et lance le chrono."),
                    seanceUUID: uuid)
    }

    /// Schedules one local notification at `fireDate`, only when it's still ahead.
    /// `seanceUUID` est embarqué dans le `userInfo` pour que le tap sur la notif
    /// (ou ses boutons) ouvre directement la séance via deep link.
    private static func scheduleOne(id: String, at fireDate: Date, title: String, body: String, seanceUUID: String) {
        guard fireDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Transporte le deep link et rattache la catégorie (boutons d'action).
        content.userInfo = ["deepLink": "mcterra://seance/\(seanceUUID)"]
        content.categoryIdentifier = "SEANCE_REMINDER"
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Removes the start + nudge reminders once the session is actually started,
    /// so she isn't nagged after she launched the timer.
    static func cancelStartNudge(for seance: Seance) {
        let base = identifier(for: seance)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [base + "-start", base + "-nudge"])
    }

    /// Body line "{client} · {lieu} · {heure}".
    private static func reminderBody(for seance: Seance) -> String {
        let client = seance.client?.name ?? ""
        let place: String
        if let location = SessionLocation(stored: seance.location) {
            place = String(localized: location.displayNameResource)
        } else {
            place = ""
        }
        let time = seance.date.formatted(date: .omitted, time: .shortened)
        return [client, place, time]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Cancel

    /// Removes all pending reminders for the given session.
    static func cancel(for seance: Seance) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: seance))
    }
}
