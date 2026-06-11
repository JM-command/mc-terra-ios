//
//  AIToolbox.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  The bridge between Claude's tool calls and Marta's real SwiftData store.
//  Each tool reads or mutates Client/Seance and returns a JSON string the model
//  can reason over. Kept @MainActor because it touches the live ModelContext.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
struct AIToolbox {
    let context: ModelContext
    /// Google connection, to mirror AI-created sessions to the calendar (optional).
    let google: GoogleCalendarService?
    /// The calendar chosen in Settings; empty when none/disconnected.
    let googleCalendarId: String

    init(context: ModelContext, google: GoogleCalendarService? = nil, googleCalendarId: String = "") {
        self.context = context
        self.google = google
        self.googleCalendarId = googleCalendarId
    }

    // MARK: - Date helpers (clinic runs on Zurich time)

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        return c
    }

    private func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = pattern
        return f
    }

    /// Parses "yyyy-MM-dd", "yyyy-MM-dd HH:mm" or "yyyy-MM-dd'T'HH:mm".
    private func parseDate(_ raw: String) -> Date? {
        let s = raw.replacingOccurrences(of: "T", with: " ").trimmingCharacters(in: .whitespaces)
        for pattern in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            if let d = formatter(pattern).date(from: s) { return d }
        }
        return nil
    }

    private func dateTimeString(_ d: Date) -> String { formatter("yyyy-MM-dd HH:mm").string(from: d) }

    // MARK: - Tool definitions sent to Claude

    static let tools: [Tool] = [
        Tool(
            name: "get_today_sessions",
            description: "Liste les séances d'aujourd'hui (heure de Zurich), triées par heure.",
            inputSchema: .from(["type": "object", "properties": [:]])
        ),
        Tool(
            name: "get_next_session",
            description: "Renvoie la prochaine séance à venir (la plus proche dans le futur).",
            inputSchema: .from(["type": "object", "properties": [:]])
        ),
        Tool(
            name: "get_sessions_on_date",
            description: "Liste les séances d'une date précise.",
            inputSchema: .from([
                "type": "object",
                "properties": ["date": ["type": "string", "description": "Date au format yyyy-MM-dd"]],
                "required": ["date"]
            ])
        ),
        Tool(
            name: "get_month_revenue",
            description: "Calcule le chiffre d'affaires d'un mois (séances terminées et payées) avec la répartition par moyen de paiement.",
            inputSchema: .from([
                "type": "object",
                "properties": ["month": ["type": "string", "description": "Mois au format yyyy-MM. Omettre pour le mois courant."]]
            ])
        ),
        Tool(
            name: "list_clients",
            description: "Liste les clients, éventuellement filtrés par un fragment de nom.",
            inputSchema: .from([
                "type": "object",
                "properties": ["query": ["type": "string", "description": "Fragment de nom à chercher (optionnel)."]]
            ])
        ),
        Tool(
            name: "get_client_sessions",
            description: "Liste les séances d'un client donné, de la plus récente à la plus ancienne.",
            inputSchema: .from([
                "type": "object",
                "properties": ["client_name": ["type": "string"]],
                "required": ["client_name"]
            ])
        ),
        Tool(
            name: "create_session",
            description: "Crée une nouvelle séance planifiée. Si le client n'existe pas encore, il est créé. Le forfait pré-remplit durée et prix, modifiables.",
            inputSchema: .from([
                "type": "object",
                "properties": [
                    "client_name": ["type": "string"],
                    "date": ["type": "string", "description": "yyyy-MM-dd HH:mm (heure de Zurich)"],
                    "service": ["type": "string", "description": "Nom d'un des forfaits existants ou un libellé libre. Le forfait pré-remplit durée et prix."],
                    "duration_minutes": ["type": "integer", "description": "Optionnel, sinon la durée par défaut du forfait."],
                    "price_chf": ["type": "number", "description": "Optionnel, sinon le prix par défaut du forfait."],
                    "location": ["type": "string", "description": "cabinet ou zoom (optionnel)."]
                ],
                "required": ["client_name", "date"]
            ])
        ),
        Tool(
            name: "update_session",
            description: "Modifie une séance existante (déplacer la date/heure, changer le forfait, la durée, le prix, le lieu ou la note). Identifier la séance par son uuid, récupéré via get_sessions_on_date ou get_client_sessions. Seuls les champs fournis sont modifiés.",
            inputSchema: .from([
                "type": "object",
                "properties": [
                    "session_uuid": ["type": "string", "description": "uuid de la séance à modifier."],
                    "date": ["type": "string", "description": "Nouvelle date au format yyyy-MM-dd HH:mm (heure de Zurich, optionnel)."],
                    "service": ["type": "string", "description": "Nouveau forfait ou libellé libre (optionnel)."],
                    "duration_minutes": ["type": "integer", "description": "Nouvelle durée en minutes (optionnel)."],
                    "price_chf": ["type": "number", "description": "Nouveau prix en CHF (optionnel)."],
                    "location": ["type": "string", "description": "cabinet ou zoom (optionnel)."],
                    "note": ["type": "string", "description": "Nouvelle note de séance (optionnel)."]
                ],
                "required": ["session_uuid"]
            ])
        ),
        Tool(
            name: "cancel_session",
            description: "Annule (supprime) une séance. Identifier la séance par son uuid, récupéré via get_sessions_on_date ou get_client_sessions.",
            inputSchema: .from([
                "type": "object",
                "properties": [
                    "session_uuid": ["type": "string", "description": "uuid de la séance à annuler."]
                ],
                "required": ["session_uuid"]
            ])
        ),
        Tool(
            name: "add_client_note",
            description: "Crée une nouvelle note horodatée dans le dossier d'un client (auteur « IA »). Apparaît dans la page Notes du client. Identifier le client par son nom.",
            inputSchema: .from([
                "type": "object",
                "properties": [
                    "client_name": ["type": "string"],
                    "text": ["type": "string", "description": "Le contenu de la note à enregistrer."]
                ],
                "required": ["client_name", "text"]
            ])
        ),
        Tool(
            name: "ask_choice",
            description: "Demande à l'utilisateur de choisir parmi des options en affichant des boutons (style messagerie). À utiliser notamment pour lever une ambiguïté de client avant de créer une séance. N'exécute aucune action : attend le clic de l'utilisateur.",
            inputSchema: .from([
                "type": "object",
                "properties": [
                    "question": ["type": "string", "description": "Question courte affichée au-dessus des boutons."],
                    "options": ["type": "array", "items": ["type": "string"], "description": "Libellés des boutons (ex : noms exacts des clients + « Nouveau client : <nom> »)."]
                ],
                "required": ["question", "options"]
            ])
        )
    ]

    // MARK: - Execution

    func execute(name: String, input: JSONValue?) -> String {
        switch name {
        case "get_today_sessions":   return getSessions(on: Date())
        case "get_next_session":     return getNextSession()
        case "get_sessions_on_date": return getSessionsOnDate(input)
        case "get_month_revenue":    return getMonthRevenue(input)
        case "list_clients":         return listClients(input)
        case "get_client_sessions":  return getClientSessions(input)
        case "create_session":       return createSession(input)
        case "update_session":       return updateSession(input)
        case "cancel_session":       return cancelSession(input)
        case "add_client_note":      return addClientNote(input)
        // Intercepted by the agent (surfaces buttons); never normally executed.
        case "ask_choice":           return jsonString(["pending": true])
        default:                     return error("Outil inconnu: \(name)")
        }
    }

    // MARK: - Read tools

    private func getSessions(on day: Date) -> String {
        let range = dayRange(day)
        let sessions = allSeances()
            .filter { $0.date >= range.start && $0.date < range.end }
            .sorted { $0.date < $1.date }
        let payload: [String: Any] = ["date": formatter("yyyy-MM-dd").string(from: day),
                                      "count": sessions.count,
                                      "sessions": sessions.map(describe)]
        return jsonString(payload)
    }

    private func getSessionsOnDate(_ input: JSONValue?) -> String {
        guard let raw = input?["date"]?.stringValue, let day = parseDate(raw) else {
            return error("Date invalide (attendu yyyy-MM-dd).")
        }
        return getSessions(on: day)
    }

    private func getNextSession() -> String {
        let now = Date()
        guard let next = allSeances().filter({ $0.date >= now }).min(by: { $0.date < $1.date }) else {
            return jsonString(["next": NSNull()])
        }
        return jsonString(["next": describe(next)])
    }

    private func getMonthRevenue(_ input: JSONValue?) -> String {
        let monthDate: Date
        if let raw = input?["month"]?.stringValue, let d = formatter("yyyy-MM").date(from: raw) {
            monthDate = d
        } else {
            monthDate = Date()
        }
        let range = monthRange(monthDate)
        let paid = allSeances().filter {
            $0.status == SeanceStatus.completed
                && $0.date >= range.start && $0.date < range.end
                && $0.priceCHF > 0
        }
        let total = paid.reduce(0.0) { $0 + $1.priceCHF }
        var byMethod: [String: Double] = [:]
        for s in paid { byMethod[s.paymentMethod, default: 0] += s.priceCHF }
        let payload: [String: Any] = [
            "month": formatter("yyyy-MM").string(from: monthDate),
            "total_chf": total,
            "paid_sessions": paid.count,
            "by_payment_method": byMethod
        ]
        return jsonString(payload)
    }

    private func listClients(_ input: JSONValue?) -> String {
        let query = input?["query"]?.stringValue?.lowercased()
        var clients = allClients()
        if let q = query, !q.isEmpty {
            clients = clients.filter { $0.name.lowercased().contains(q) }
        }
        clients.sort { $0.name < $1.name }
        let rows: [[String: Any]] = clients.map {
            ["name": $0.name, "phone": $0.phone, "language": $0.language, "sessions": $0.seances.count]
        }
        let payload: [String: Any] = ["count": clients.count, "clients": rows]
        return jsonString(payload)
    }

    private func getClientSessions(_ input: JSONValue?) -> String {
        guard let name = input?["client_name"]?.stringValue else { return error("client_name manquant.") }
        guard let client = findClient(name) else { return jsonString(["found": false, "query": name]) }
        let sessions = client.seances.sorted { $0.date > $1.date }
        let payload: [String: Any] = ["found": true, "client": client.name,
                                      "count": sessions.count, "sessions": sessions.map(describe)]
        return jsonString(payload)
    }

    // MARK: - Write tools

    private func createSession(_ input: JSONValue?) -> String {
        guard let name = input?["client_name"]?.stringValue else { return error("client_name manquant.") }
        guard let rawDate = input?["date"]?.stringValue, let date = parseDate(rawDate) else {
            return error("Date invalide (attendu yyyy-MM-dd HH:mm).")
        }

        let client = findClient(name) ?? {
            let c = Client(name: name)
            context.insert(c)
            return c
        }()

        // Resolve the forfait: match an existing Forfait by name, else free label.
        // Fall back to the first forfait when the model didn't specify a service.
        let forfaits = allForfaits()
        let serviceLabel = input?["service"]?.stringValue ?? forfaits.first?.name ?? ""
        let matched = forfaits.first {
            $0.name.caseInsensitiveCompare(serviceLabel) == .orderedSame
        }
        let duration = input?["duration_minutes"]?.intValue
            ?? matched?.durationMinutes ?? 60
        let price = input?["price_chf"]?.doubleValue
            ?? matched?.priceCHF ?? 0
        let location = input?["location"]?.stringValue.flatMap { SessionLocation(stored: $0)?.rawValue } ?? ""

        let seance = Seance(
            date: date,
            serviceName: matched?.name ?? serviceLabel,
            durationMinutes: duration,
            priceCHF: price,
            location: location,
            client: client
        )
        context.insert(seance)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        // Planifie le rappel local et resync la liste push (sinon séance "muette").
        NotificationService.schedule(for: seance)
        PushToStartService.shared.sync(using: context)
        pushToGoogle(seance)

        return jsonString(["created": true, "session": describe(seance)])
    }

    /// Mirrors an AI-created session to Google Calendar when connected (best-effort,
    /// fire-and-forget; offline / signed-out simply no-ops).
    private func pushToGoogle(_ seance: Seance) {
        guard let google, google.isSignedIn, !googleCalendarId.isEmpty,
              seance.googleEventId.isEmpty else { return }
        let calendarId = googleCalendarId
        Task { @MainActor in
            if let id = await google.createEvent(calendarId: calendarId, for: seance) {
                seance.googleEventId = id
            }
        }
    }

    private func updateSession(_ input: JSONValue?) -> String {
        guard let raw = input?["session_uuid"]?.stringValue, let uuid = UUID(uuidString: raw) else {
            return error("session_uuid manquant ou invalide.")
        }
        guard let seance = findSeance(uuid) else { return jsonString(["found": false, "uuid": raw]) }

        if let rawDate = input?["date"]?.stringValue {
            guard let date = parseDate(rawDate) else {
                return error("Date invalide (attendu yyyy-MM-dd HH:mm).")
            }
            seance.date = date
        }
        var matchedForfait: Forfait?
        if let serviceLabel = input?["service"]?.stringValue {
            // Match an existing Forfait by name, else keep the free label.
            matchedForfait = allForfaits().first {
                $0.name.caseInsensitiveCompare(serviceLabel) == .orderedSame
            }
            seance.serviceName = matchedForfait?.name ?? serviceLabel
        }
        // When a forfait was matched and the model didn't override them, pull its
        // default duration and price (mirrors the create flow's pre-fill).
        if let duration = input?["duration_minutes"]?.intValue {
            seance.durationMinutes = duration
        } else if let forfait = matchedForfait {
            seance.durationMinutes = forfait.durationMinutes
        }
        if let price = input?["price_chf"]?.doubleValue {
            seance.priceCHF = price
        } else if let forfait = matchedForfait {
            seance.priceCHF = forfait.priceCHF
        }
        if let rawLocation = input?["location"]?.stringValue,
           let location = SessionLocation(stored: rawLocation)?.rawValue {
            seance.location = location
        }
        if let note = input?["note"]?.stringValue {
            seance.note = note
        }

        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        // Re-planifie le rappel (schedule annule l'ancien en interne, safe même si
        // la date n'a pas bougé) et resync le push (sinon ancien timer lock-screen).
        NotificationService.schedule(for: seance)
        PushToStartService.shared.sync(using: context)

        // Mirror the change to Google when the session is already linked (best-effort).
        if !seance.googleEventId.isEmpty, let google, google.isSignedIn, !googleCalendarId.isEmpty {
            let calendarId = googleCalendarId
            let eventId = seance.googleEventId
            Task { @MainActor in
                await google.updateEvent(calendarId: calendarId, eventId: eventId, for: seance)
            }
        }

        return jsonString(["updated": true, "session": describe(seance)])
    }

    private func cancelSession(_ input: JSONValue?) -> String {
        guard let raw = input?["session_uuid"]?.stringValue, let uuid = UUID(uuidString: raw) else {
            return error("session_uuid manquant ou invalide.")
        }
        guard let seance = findSeance(uuid) else { return jsonString(["found": false, "uuid": raw]) }

        // Remove the linked Google event when connected (best-effort, fire-and-forget).
        if !seance.googleEventId.isEmpty, let google, google.isSignedIn, !googleCalendarId.isEmpty {
            let calendarId = googleCalendarId
            let eventId = seance.googleEventId
            Task { @MainActor in
                await google.deleteEvent(calendarId: calendarId, eventId: eventId)
            }
        }

        NotificationService.cancel(for: seance)
        context.delete(seance)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        // Resync la liste push après suppression (sinon timer pour séance morte).
        PushToStartService.shared.sync(using: context)

        return jsonString(["cancelled": true])
    }

    private func addClientNote(_ input: JSONValue?) -> String {
        guard let name = input?["client_name"]?.stringValue else { return error("client_name manquant.") }
        // Accepte "text" (nouveau schéma) ou "note" (ancien) pour rétro-compat.
        guard let text = input?["text"]?.stringValue ?? input?["note"]?.stringValue,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return error("text manquant.")
        }
        guard let client = findClient(name) else { return jsonString(["found": false, "query": name]) }
        // Crée une vraie Note horodatée, auteur "ia", rattachée au client.
        let note = Note(text: text, author: "ia", client: client)
        context.insert(note)
        try? context.save()
        return jsonString(["created": true, "client": client.name, "note": text])
    }

    // MARK: - Store access

    private func allSeances() -> [Seance] {
        (try? context.fetch(FetchDescriptor<Seance>())) ?? []
    }

    private func allClients() -> [Client] {
        (try? context.fetch(FetchDescriptor<Client>())) ?? []
    }

    /// Marta's forfaits, ordered as in Settings, used to resolve a session's service.
    private func allForfaits() -> [Forfait] {
        let descriptor = FetchDescriptor<Forfait>(
            sortBy: [SortDescriptor(\Forfait.sortOrder), SortDescriptor(\Forfait.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Exact match first, then a case-insensitive contains, so "Sophie" finds
    /// "Sophie Martin".
    private func findClient(_ name: String) -> Client? {
        let clients = allClients()
        let q = name.lowercased()
        return clients.first { $0.name.lowercased() == q }
            ?? clients.first { $0.name.lowercased().contains(q) }
    }

    /// Looks up a session by its uuid (the AI gets uuids back from the list tools).
    private func findSeance(_ uuid: UUID) -> Seance? {
        var descriptor = FetchDescriptor<Seance>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func describe(_ s: Seance) -> [String: Any] {
        [
            "uuid": s.uuid.uuidString,
            "client": s.client?.name ?? "Sans client",
            "date": dateTimeString(s.date),
            "service": s.serviceName,
            "duration_min": s.durationMinutes,
            "price_chf": s.priceCHF,
            "status": s.status,
            "payment": s.paymentMethod,
            "location": s.location,
            "note": s.note
        ]
    }

    // MARK: - Calendar ranges

    private func dayRange(_ day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private func monthRange(_ day: Date) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: day)
        let start = calendar.date(from: comps) ?? day
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    // MARK: - Output

    private func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private func error(_ message: String) -> String { jsonString(["error": message]) }
}
