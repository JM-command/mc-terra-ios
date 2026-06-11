//
//  GoogleCalendarService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Combine
import Foundation
import SwiftData
import GoogleSignIn
import WidgetKit

/// Errors surfaced by the Google Calendar integration. Kept human-readable so the
/// UI can show them directly without crashing when offline or signed out.
enum GoogleCalendarError: LocalizedError {
    case notSignedIn
    case missingScope
    case noPresenter
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(localized: "Non connecté à Google.")
        case .missingScope: return String(localized: "Accès à l'agenda non autorisé.")
        case .noPresenter: return String(localized: "Impossible d'afficher la connexion Google.")
        case .http(let code): return String(localized: "Erreur réseau Google (\(code)).")
        case .decoding: return String(localized: "Réponse Google illisible.")
        }
    }
}

/// Connects to Google Calendar (read-only for now): sign-in, calendar listing,
/// and importing upcoming events into local `Seance` records.
///
/// Phase A is read-only (Google → app). Pushing app sessions back to Google is a
/// later phase. Every method fails gracefully (throws, never crashes) so the app
/// keeps working offline or while signed out.
@MainActor
final class GoogleCalendarService: ObservableObject {

    /// The calendar read+write scope we request alongside basic sign-in. Phase B
    /// pushes app sessions back to Google, so we need write access (not just
    /// `calendar.readonly`). Users who previously consented in read-only get a
    /// scope-elevation prompt the next time they sign in (see `signIn`).
    static let calendarScope = "https://www.googleapis.com/auth/calendar"

    /// Whether a Google account is currently connected with the calendar scope.
    @Published var isSignedIn = false
    /// The connected account's email, shown in Settings.
    @Published var email: String?

    // MARK: - Session lifecycle

    /// Restores a previous sign-in silently at launch. Safe to call when no
    /// session exists — it simply leaves `isSignedIn` false.
    func restore() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            updateState(from: nil)
            return
        }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            updateState(from: user)
        } catch {
            updateState(from: nil)
        }
    }

    /// Presents the Google sign-in flow and requests the calendar (read+write)
    /// scope. On success, stores the connected state and email.
    ///
    /// Scope elevation: a user who previously consented in read-only is already
    /// signed in but lacks the write scope. In that case we call `addScopes` on the
    /// current user to trigger a re-consent for the broader `calendar` scope,
    /// instead of starting a brand-new sign-in.
    func signIn(presenting: UIViewController) async throws {
        // Already signed in (e.g. read-only from Phase A) but missing the write
        // scope: request an upgrade rather than a fresh sign-in.
        if let current = GIDSignIn.sharedInstance.currentUser, !hasCalendarScope(current) {
            let granted = try await current.addScopes([Self.calendarScope], presenting: presenting)
            guard hasCalendarScope(granted.user) else {
                throw GoogleCalendarError.missingScope
            }
            updateState(from: granted.user)
            return
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenting,
            hint: nil,
            additionalScopes: [Self.calendarScope]
        )
        var user = result.user

        // The user may sign in but decline the calendar scope; request it explicitly.
        if !hasCalendarScope(user) {
            let granted = try await user.addScopes([Self.calendarScope], presenting: presenting)
            user = granted.user
        }

        guard hasCalendarScope(user) else {
            throw GoogleCalendarError.missingScope
        }
        updateState(from: user)
    }

    /// Disconnects the current Google account.
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        updateState(from: nil)
    }

    // MARK: - Token

    /// Returns a valid OAuth access token, refreshing it when needed.
    func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleCalendarError.notSignedIn
        }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }

    // MARK: - Calendar list

    /// Fetches the user's calendars (id + display name) for the Settings picker.
    func listCalendars() async throws -> [(id: String, summary: String)] {
        let token = try await accessToken()
        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        let data = try await get(url, token: token)

        do {
            let decoded = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            return decoded.items.map { (id: $0.id, summary: $0.summary ?? $0.id) }
        } catch {
            throw GoogleCalendarError.decoding
        }
    }

    // MARK: - Events

    /// Fetches events of a calendar between two dates (expanded, time-ordered).
    func fetchEvents(calendarId: String, from: Date, to: Date) async throws -> [GoogleEvent] {
        let token = try await accessToken()

        var components = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarId))/events"
        )!
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]

        let data = try await get(components.url!, token: token)
        do {
            let decoded = try JSONDecoder().decode(EventListResponse.self, from: data)
            return decoded.items
        } catch {
            throw GoogleCalendarError.decoding
        }
    }

    // MARK: - Import

    /// Imports the next ~90 days of events into local `Seance` records, creating
    /// or updating one session per Google event (matched by `googleEventId`).
    /// Never produces duplicates. Saves the context when done.
    func `import`(into context: ModelContext, calendarId: String) async throws {
        let from = Date.now
        let to = Calendar.current.date(byAdding: .day, value: 90, to: from) ?? from
        let events = try await fetchEvents(calendarId: calendarId, from: from, to: to)

        // Cache existing clients once so we can match names without re-querying.
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []

        for event in events {
            // Only timed events have dateTime; all-day events (date only) are skipped.
            guard let start = event.startDate, let end = event.endDate else { continue }

            let eventId = event.id
            let summary = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (summary?.isEmpty == false) ? summary! : String(localized: "Rendez-vous")
            let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
            let matched = matchClient(in: clients, summary: summary)

            if let existing = try existingSeance(in: context, eventId: eventId) {
                // Update in place; keep locally-edited note/price intact.
                existing.date = start
                existing.durationMinutes = minutes
                existing.serviceName = title
                existing.status = SeanceStatus.planned
                if existing.client == nil { existing.client = matched }
            } else {
                let seance = Seance(
                    date: start,
                    serviceName: title,
                    durationMinutes: minutes,
                    priceCHF: 0,
                    status: SeanceStatus.planned,
                    googleEventId: eventId,
                    client: matched
                )
                context.insert(seance)
            }
        }

        try context.save()
        // Reflect the freshly imported sessions in the home-screen widgets.
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Push (app → Google)

    /// Creates a Google Calendar event mirroring a local session. Returns the new
    /// event id on success, or `nil` if anything goes wrong (offline, signed out,
    /// missing write scope). Never throws so callers can fire-and-forget without
    /// blocking the UI.
    ///
    /// - summary: client name + " - " + serviceName, or just serviceName when the
    ///   session has no client.
    /// - start: `seance.date`; end: start + `durationMinutes` minutes.
    func createEvent(calendarId: String, for seance: Seance) async -> String? {
        // Online sessions request an auto-generated Google Meet link (needs the
        // conferenceDataVersion=1 query for Google to honour the create request).
        let online = SessionLocation(stored: seance.location) == .online
        let body = eventBody(for: seance, includeConferenceRequest: online)
        do {
            let token = try await accessToken()
            let suffix = online ? "?conferenceDataVersion=1" : ""
            let url = URL(
                string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarId))/events\(suffix)"
            )!
            let data = try await send(url, method: "POST", token: token, jsonBody: body)
            let decoded = try JSONDecoder().decode(EventIdResponse.self, from: data)
            return decoded.id
        } catch {
            return nil
        }
    }

    /// Patches an existing Google Calendar event to match the local session.
    /// Silently no-ops on failure (offline, signed out, missing write scope).
    func updateEvent(calendarId: String, eventId: String, for seance: Seance) async {
        let body = eventBody(for: seance)
        do {
            let token = try await accessToken()
            let url = URL(
                string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarId))/events/\(encode(eventId))"
            )!
            _ = try await send(url, method: "PATCH", token: token, jsonBody: body)
        } catch {
            // Best-effort: leave the local session untouched and don't surface a crash.
        }
    }

    /// Deletes a Google Calendar event. Silently no-ops on failure. A 404/410
    /// (already gone) is treated as success-enough — the event no longer exists.
    func deleteEvent(calendarId: String, eventId: String) async {
        do {
            let token = try await accessToken()
            let url = URL(
                string: "https://www.googleapis.com/calendar/v3/calendars/\(encode(calendarId))/events/\(encode(eventId))"
            )!
            _ = try await send(url, method: "DELETE", token: token, jsonBody: nil)
        } catch GoogleCalendarError.http(404), GoogleCalendarError.http(410) {
            // Event already removed on Google's side: nothing to do.
        } catch {
            // Best-effort: don't surface a crash if offline / signed out.
        }
    }

    /// Builds the Calendar API request body for a session: summary, start and end
    /// (both in `Europe/Zurich`). Reused by create and update.
    private func eventBody(for seance: Seance, includeConferenceRequest: Bool = false) -> [String: Any] {
        let clientName = seance.client?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String
        if let clientName, !clientName.isEmpty {
            summary = "\(clientName) - \(seance.serviceName)"
        } else {
            summary = seance.serviceName
        }

        let start = seance.date
        let end = start.addingTimeInterval(TimeInterval(max(0, seance.durationMinutes) * 60))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var body: [String: Any] = [
            "summary": summary,
            "start": [
                "dateTime": formatter.string(from: start),
                "timeZone": "Europe/Zurich"
            ],
            "end": [
                "dateTime": formatter.string(from: end),
                "timeZone": "Europe/Zurich"
            ]
        ]

        // Ask Google to create a Meet link for online sessions (create only, so
        // updates don't try to recreate an existing conference).
        if includeConferenceRequest {
            body["conferenceData"] = [
                "createRequest": [
                    "requestId": UUID().uuidString,
                    "conferenceSolutionKey": ["type": "hangoutsMeet"]
                ]
            ]
        }

        return body
    }

    // MARK: - Helpers

    /// Looks up an already-imported session by its Google event id.
    private func existingSeance(in context: ModelContext, eventId: String) throws -> Seance? {
        var descriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { $0.googleEventId == eventId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Tries to find a client whose name appears in the event summary.
    private func matchClient(in clients: [Client], summary: String?) -> Client? {
        guard let summary, !summary.isEmpty else { return nil }
        let lowered = summary.lowercased()
        return clients.first { client in
            let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && lowered.contains(name.lowercased())
        }
    }

    /// True when the user has granted the calendar scope.
    private func hasCalendarScope(_ user: GIDGoogleUser) -> Bool {
        user.grantedScopes?.contains(Self.calendarScope) ?? false
    }

    /// Reflects the user into the published state on the main actor.
    private func updateState(from user: GIDGoogleUser?) {
        if let user, hasCalendarScope(user) {
            isSignedIn = true
            email = user.profile?.email
        } else {
            isSignedIn = false
            email = nil
        }
    }

    /// Percent-encodes a path component (calendar ids can contain `@`, `#`, etc.).
    private func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// Performs an authenticated GET and returns the body, throwing on HTTP errors.
    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GoogleCalendarError.http(http.statusCode)
        }
        return data
    }

    /// Performs an authenticated mutating request (POST/PATCH/DELETE) with an
    /// optional JSON body, returning the response body. A 403 is mapped to
    /// `.missingScope` (the user consented in read-only and lacks write access).
    private func send(
        _ url: URL,
        method: String,
        token: String,
        jsonBody: [String: Any]?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // 403 here almost always means the write scope wasn't granted.
            if http.statusCode == 403 { throw GoogleCalendarError.missingScope }
            throw GoogleCalendarError.http(http.statusCode)
        }
        return data
    }
}

// MARK: - Wire format

/// Calendar list endpoint response.
private struct CalendarListResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let summary: String?
    }
    let items: [Item]
}

/// Events list endpoint response.
private struct EventListResponse: Decodable {
    let items: [GoogleEvent]
}

/// Minimal response of an event insert/patch: just the event id we persist.
private struct EventIdResponse: Decodable {
    let id: String
}

/// A single Google Calendar event (only the fields we need).
struct GoogleEvent: Decodable {
    struct EventDate: Decodable {
        /// RFC3339 timestamp for timed events (e.g. "2026-06-10T14:00:00+02:00").
        let dateTime: String?
        /// "YYYY-MM-DD" for all-day events (we skip these in Phase A).
        let date: String?
    }

    let id: String
    let summary: String?
    let start: EventDate?
    let end: EventDate?

    /// Parsed start, or nil for all-day events / missing data.
    var startDate: Date? { Self.parse(start?.dateTime) }
    /// Parsed end, or nil for all-day events / missing data.
    var endDate: Date? { Self.parse(end?.dateTime) }

    /// Parses an RFC3339 string, tolerating fractional seconds.
    private static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
