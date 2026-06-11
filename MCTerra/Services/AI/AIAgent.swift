//
//  AIAgent.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Drives the command bar: takes what Marta typed/said, lets Claude read and act
//  on her data through the toolbox, and returns the final French reply. Runs the
//  tool-use loop (call tool → feed result back → repeat until Claude answers).
//

import Foundation
import SwiftData

/// What the agent returns for one turn: the text to show, plus optional tappable
/// quick-reply buttons (Telegram style) when the AI asks the user to choose.
struct AgentReply {
    let text: String
    var suggestions: [String] = []
}

@MainActor
final class AIAgent {
    private let toolbox: AIToolbox
    /// App language ("fr"/"pt"); drives the reply language and localized fallbacks.
    private let language: String

    /// Safety cap on tool rounds so a confused model can't loop forever.
    private let maxRounds = 6

    init(context: ModelContext, language: String = "fr", google: GoogleCalendarService? = nil, googleCalendarId: String = "") {
        self.toolbox = AIToolbox(context: context, google: google, googleCalendarId: googleCalendarId)
        self.language = language
    }

    /// The locale used to localize the agent's own fixed messages.
    private var locale: Locale { Locale(identifier: language) }

    /// Sends `userText` (plus the visible conversation as context) and returns
    /// Claude's answer. Tool calls happen internally; an `ask_choice` call surfaces
    /// quick-reply buttons instead of continuing silently.
    func respond(to userText: String, history: [(role: String, text: String)]) async throws -> AgentReply {
        var messages: [Message] = history.map {
            Message(role: $0.role, content: .text($0.text))
        }
        messages.append(.user(userText))

        for _ in 0..<maxRounds {
            let response = try await AnthropicClient.shared.send(
                system: systemPrompt(),
                tools: AIToolbox.tools,
                messages: messages
            )

            let toolUses = response.content.filter { $0.type == "tool_use" }

            // The model wants the user to pick: surface the question + buttons, stop.
            if let ask = toolUses.first(where: { $0.name == "ask_choice" }) {
                let leading = response.content.compactMap(\.text).joined(separator: "\n")
                let question = ask.input?["question"]?.stringValue
                    ?? (leading.isEmpty ? String(localized: "Quel client ?", locale: locale) : leading)
                let options = ask.input?["options"]?.stringArray ?? []
                return AgentReply(text: question, suggestions: options)
            }

            if toolUses.isEmpty {
                let text = response.content.compactMap(\.text).joined(separator: "\n")
                return AgentReply(text: text.isEmpty ? String(localized: "D'accord.", locale: locale) : text)
            }

            // Echo the assistant turn (text + tool_use), then answer each tool call.
            messages.append(.assistant(response.content))
            let results = toolUses.map { tu in
                ContentBlock.toolResult(
                    id: tu.id ?? "",
                    toolbox.execute(name: tu.name ?? "", input: tu.input)
                )
            }
            messages.append(.toolResults(results))
        }

        return AgentReply(text: String(
            localized: "Je n'ai pas réussi à terminer la demande. Tu peux reformuler ?",
            locale: locale
        ))
    }

    // MARK: - System prompt

    private func systemPrompt() -> String {
        let today = todayString()
        // The reply language follows the app language so a PT user gets PT answers.
        let replyLanguage = language == "pt"
            ? "en portugais du Portugal (PT-PT, jamais brésilien)"
            : "en français"
        return """
        Tu es l'assistante personnelle de Marta Coelho, coach et thérapeute (MC-TERRA), \
        directement dans son app de gestion. Tu l'aides à gérer ses clients, ses séances, \
        son agenda et ses revenus.

        Date du jour : \(today) (fuseau Europe/Zurich).

        Règles :
        - Réponds toujours \(replyLanguage), de façon courte, chaleureuse et concrète.
        - Utilise les outils pour LIRE et AGIR sur les vraies données. N'invente jamais un \
        client, une séance ou un montant : si tu ne sais pas, utilise un outil ou demande.
        - Pour une action (créer une séance, ajouter une note), fais-la avec l'outil puis \
        confirme en une phrase ce qui a été fait (qui, quand, quel forfait).
        - Les montants sont en CHF. Les forfaits : Séance Découverte, Thérapie Émotionnelle, \
        Massage aux Huiles Essentielles, Constellation Individuelle, Constellation en Groupe.
        - Si une demande est ambiguë (date sans heure, client homonyme), demande une précision \
        courte plutôt que de deviner.

        Modifier ou annuler une séance :
        - Pour modifier, déplacer ou annuler une séance, commence par lister les séances \
        concernées (`get_sessions_on_date` pour une date, `get_client_sessions` pour un client) \
        afin de récupérer le `uuid` exact de la bonne séance.
        - Appelle ensuite `update_session` (avec seulement les champs à changer) ou \
        `cancel_session`, en passant ce `uuid`.
        - S'il y a plusieurs séances possibles, demande laquelle (ou utilise `ask_choice`) \
        avant d'agir. Une fois fait, confirme l'action en une phrase courte.

        Choix du client (TRÈS IMPORTANT, pour éviter les doublons) :
        - Avant de créer une séance, appelle `list_clients` avec le nom (ou un fragment) pour \
        voir les clients existants.
        - S'il y a UN client qui correspond exactement, utilise-le (passe son nom exact à \
        `create_session`).
        - S'il y a plusieurs candidats, OU un nom proche mais pas identique, OU aucun client, \
        n'invente RIEN : appelle `ask_choice` avec une question courte et des `options` = les \
        noms exacts des clients proches PLUS une option « Nouveau client : <nom> ». L'utilisateur \
        tape un bouton, tu crées ensuite la séance avec ce choix.
        - Ne crée un nouveau client QUE si l'utilisateur a explicitement choisi « Nouveau client ».

        Mise en forme (IMPORTANT) :
        - JAMAIS d'emoji.
        - JAMAIS de tiret cadratin « — ». Utilise une virgule, des parenthèses ou un point.
        - JAMAIS de tableau Markdown (pas de « | »). Pour plusieurs séances, fais une ligne par \
        séance avec un tiret simple, par ex. : « - 10h00, Daniel, Constellation en Groupe \
        (Cabinet), planifiée ». Sinon réponds en phrases courtes.
        - Pas de jargon technique. Marta veut une réponse claire, comme un bon assistant humain.
        """
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: Date())
    }
}
