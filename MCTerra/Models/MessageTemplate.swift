//
//  MessageTemplate.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

/// One labelled option in an options picker — a display label (in the app's
/// language) mapped to the raw value the picker actually selects.
///
/// Used both by the retreat picker (label "Juin" → value `"rjuin"`) and by the
/// duration unit picker (label "semaines" → value `"weeks"`).
struct MessageTemplateOption: Identifiable, Hashable {
    /// Display label shown in the picker (localized to the app's language).
    let label: LocalizedStringKey
    /// Raw value selected when this option is picked (e.g. a slug or a unit key).
    let value: String

    var id: String { value }

    // Identity is the raw value; the label is presentation only. This also avoids
    // relying on `LocalizedStringKey` Hashable synthesis across iOS versions.
    static func == (lhs: MessageTemplateOption, rhs: MessageTemplateOption) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

/// The kind of input a `MessageTemplateField` collects, and how it renders.
///
/// - `text`: a free-text field (legacy behaviour, no longer used by the catalogue
///   but kept so future templates can still ask for arbitrary text).
/// - `number`: an integer picked from `range`, paired with a `unit` picker whose
///   options describe the unit (e.g. days / weeks / months).
/// - `options`: a single value chosen from a fixed list (e.g. a known retreat).
enum MessageTemplateFieldKind {
    case text
    case number(range: ClosedRange<Int>, unit: [MessageTemplateOption])
    case options([MessageTemplateOption])
}

/// Describes one optional field a template needs before it can be sent
/// (e.g. "how long since we last spoke", or which retreat to invite to).
///
/// The prompt label is a `LocalizedStringKey` (UI is shown in the app's language).
/// The collected value(s) are resolved into the substitution tokens applied to the
/// message body via `resolve` — e.g. `{duration}` or `{link}`.
struct MessageTemplateField {
    /// The token replaced in the body, without braces — e.g. `"duration"` for `{duration}`.
    let placeholder: String
    /// Label shown above the picker(s) / field in the form sheet.
    let prompt: LocalizedStringKey
    /// What kind of input this field collects (text, number+unit, or options).
    let kind: MessageTemplateFieldKind
    /// Value the (text/options) field starts with, or the number's unit, encoded as a string.
    let defaultValue: String
    /// Maps the resolved raw input + client into the substitution tokens to apply.
    ///
    /// For text/options the raw input is the picked value (slug, or typed text).
    /// For number fields the raw input is encoded as `"<count>|<unit>"`, which the
    /// reconnect template decodes into a localized, singular-aware "N jours" string.
    let resolve: (_ rawInput: String, _ client: Client) -> [String: String]

    init(
        placeholder: String,
        prompt: LocalizedStringKey,
        kind: MessageTemplateFieldKind = .text,
        defaultValue: String = "",
        resolve: ((_ rawInput: String, _ client: Client) -> [String: String])? = nil
    ) {
        self.placeholder = placeholder
        self.prompt = prompt
        self.kind = kind
        self.defaultValue = defaultValue
        // Default: substitute this field's own placeholder with the raw value.
        self.resolve = resolve ?? { input, _ in [placeholder: input] }
    }
}

// MARK: - Duration units

/// The unit used by the "reconnect" duration picker (days / weeks / months).
///
/// Knows how to render itself with the correct singular/plural form in the
/// *client's* language (FR or PT-PT) — e.g. `1 → "1 jour"`, `3 → "3 semanas"`.
enum DurationUnit: String, CaseIterable {
    case days
    case weeks
    case months

    /// Options for the unit picker, labelled in the app's language (plural form).
    static let options: [MessageTemplateOption] = [
        MessageTemplateOption(label: "jours", value: DurationUnit.days.rawValue),
        MessageTemplateOption(label: "semaines", value: DurationUnit.weeks.rawValue),
        MessageTemplateOption(label: "mois", value: DurationUnit.months.rawValue),
    ]

    /// French word for this unit, singular or plural.
    private func french(singular: Bool) -> String {
        switch self {
        case .days: return singular ? "jour" : "jours"
        case .weeks: return singular ? "semaine" : "semaines"
        case .months: return "mois" // invariant in French
        }
    }

    /// Portuguese (PT-PT) word for this unit, singular or plural.
    private func portuguese(singular: Bool) -> String {
        switch self {
        case .days: return singular ? "dia" : "dias"
        case .weeks: return singular ? "semana" : "semanas"
        case .months: return singular ? "mês" : "meses"
        }
    }

    /// Renders "N <unit>" in the client's language with the right singular/plural form.
    func localized(count: Int, language: String) -> String {
        let singular = count == 1
        let word = language == "pt" ? portuguese(singular: singular) : french(singular: singular)
        return "\(count) \(word)"
    }

    /// Decodes a `"<count>|<unit>"` raw value and renders the localized duration.
    /// Falls back to "1 jour" / "1 dia" if the encoding can't be parsed.
    static func localizedDuration(from rawInput: String, language: String) -> String {
        let parts = rawInput.split(separator: "|", maxSplits: 1).map(String.init)
        let count = parts.first.flatMap { Int($0) } ?? 1
        let unit = parts.count > 1 ? DurationUnit(rawValue: parts[1]) ?? .days : .days
        return unit.localized(count: count, language: language)
    }
}

/// A ready-to-send WhatsApp message template.
///
/// The body is produced in the *client's* language (`"fr"` or `"pt"`), not the app
/// locale — Marta writes to each client in their own tongue. `{name}` is always
/// replaced by the client's name; extra placeholders come from `field` (if any).
struct MessageTemplate: Identifiable {
    let id: String
    /// SF Symbol name shown in the list row.
    let icon: String
    /// Row title, shown in the app's language.
    let title: LocalizedStringKey
    /// Optional form field collected in a sheet before sending.
    let field: MessageTemplateField?

    /// French body, with placeholders like `{name}` still present.
    private let frenchBody: String
    /// Portuguese (PT-PT) body, with placeholders like `{name}` still present.
    private let portugueseBody: String

    /// Builds the final message body for a client, in the client's language,
    /// substituting `{name}` and any extra `values` (keyed by placeholder token).
    func body(for client: Client, values: [String: String] = [:]) -> String {
        var text = client.language == "pt" ? portugueseBody : frenchBody
        text = text.replacingOccurrences(of: "{name}", with: client.name)
        for (placeholder, value) in values {
            text = text.replacingOccurrences(of: "{\(placeholder)}", with: value)
        }
        return text
    }
}

// MARK: - Catalogue

extension MessageTemplate {
    /// The four ready-to-send templates, in display order.
    static let all: [MessageTemplate] = [
        welcome,
        reconnect,
        retreatInvitation,
        proposeSession,
    ]

    // MARK: 1 — Community welcome (no form)

    static let welcome = MessageTemplate(
        id: "welcome",
        icon: "hands.sparkles.fill",
        title: "Bienvenue communauté",
        field: nil,
        frenchBody: """
        🌺 Message de bienvenue dans la communauté MC-TERRA 🌺
        Notre chère {name}
        Bienvenue dans cet espace de guérison, de respect et d'amour.
        Ici, chacun avance à son propre rythme, avec son histoire, sa sensibilité et son chemin unique.
        Ce groupe est un cercle de confiance.
        L'écoute y est précieuse, le partage y est sincère, et le silence y a toute sa place.
        Nous choisissons de cultiver la présence, la douceur et l'accueil de ce qui se vit, simplement, sans jugement.
        Que cet espace devienne pour toi une terre fertile pour grandir, un refuge de lumière, un lieu où le cœur peut se déposer et l'esprit s'ouvrir en toute sécurité.
        Nous sommes heureux de t'accueillir parmi nous 💛
        Blog : https://mc-terra.ch/fr/posts
        Groupe WhatsApp : https://chat.whatsapp.com/BFY1wV8yNDV0XmbhOJqPq7
        """,
        portugueseBody: """
        🌺 Mensagem de boas-vindas à comunidade MC-TERRA 🌺
        Querida {name}
        Bem-vinda a este espaço de cura, de respeito e de amor.
        Aqui, cada pessoa avança ao seu próprio ritmo, com a sua história, a sua sensibilidade e o seu caminho único.
        Este grupo é um círculo de confiança.
        A escuta é preciosa, a partilha é sincera, e o silêncio tem todo o seu lugar.
        Escolhemos cultivar a presença, a doçura e o acolhimento daquilo que se vive, simplesmente, sem julgamento.
        Que este espaço se torne para ti uma terra fértil para crescer, um refúgio de luz, um lugar onde o coração se pode pousar e o espírito se abrir em total segurança.
        Estamos felizes por te acolher entre nós 💛
        Blog: https://mc-terra.ch/pt/posts
        Grupo WhatsApp: https://chat.whatsapp.com/GRKmii523u7IykpdzJlT0P
        """
    )

    // MARK: 2 — Reconnect (form: how long since we last spoke)

    static let reconnect = MessageTemplate(
        id: "reconnect",
        icon: "hand.wave.fill",
        title: "Reprise de contact",
        field: MessageTemplateField(
            placeholder: "duration",
            prompt: "Depuis combien de temps ?",
            kind: .number(range: 1...12, unit: DurationUnit.options),
            // Start at "1" + the first unit (days), encoded as "<count>|<unit>".
            defaultValue: "1|\(DurationUnit.days.rawValue)",
            // Decode "<count>|<unit>" and render a singular-aware, localized duration.
            resolve: { rawInput, client in
                ["duration": DurationUnit.localizedDuration(from: rawInput, language: client.language)]
            }
        ),
        frenchBody: """
        Bonjour {name}, j'espère que tu vas bien 💛 Ça fait {duration} qu'on ne s'est pas parlé, et j'avais envie de prendre de tes nouvelles. Si tu en ressens le besoin, je serais heureuse de te revoir. Prends soin de toi 🌸
        """,
        portugueseBody: """
        Olá {name}, espero que estejas bem 💛 Já passou {duration} desde a última vez que falámos, e tive vontade de saber de ti. Se sentires necessidade, teria muito gosto em ver-te de novo. Cuida de ti 🌸
        """
    )

    // MARK: 3 — Retreat invitation (form: pick a known retreat, pre-selected "rjuin")

    /// Known retreats offered in the picker — display label (FR/PT app language)
    /// mapped to the page slug used in the URL. Extend this list as retreats are added.
    static let knownRetreats: [MessageTemplateOption] = [
        MessageTemplateOption(label: "Mai", value: "rmai"),
        MessageTemplateOption(label: "Juin", value: "rjuin"),
    ]

    static let retreatInvitation = MessageTemplate(
        id: "retreatInvitation",
        icon: "leaf.fill",
        title: "Invitation retraite nature",
        field: MessageTemplateField(
            placeholder: "link",
            prompt: "Quelle retraite ?",
            kind: .options(knownRetreats),
            defaultValue: "rjuin",
            // Turn the picked slug into a full localized page URL substituted as {link}.
            resolve: { slug, client in
                let lang = client.language == "pt" ? "pt" : "fr"
                let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
                return ["link": "https://mc-terra.ch/\(lang)/p/\(trimmed)"]
            }
        ),
        frenchBody: """
        Bonjour {name} 🌿 Je t'invite à notre prochaine retraite dans la nature, un week-end de 2 jours pour se reconnecter à soi 💛 Toutes les infos ici : {link}. J'espère t'y voir 🌸
        """,
        portugueseBody: """
        Olá {name} 🌿 Convido-te para o nosso próximo retiro na natureza, um fim de semana de 2 dias para te reconectares contigo 💛 Todas as informações aqui: {link}. Espero ver-te lá 🌸
        """
    )

    // MARK: 4 — Propose a session (no form)

    static let proposeSession = MessageTemplate(
        id: "proposeSession",
        icon: "calendar.badge.plus",
        title: "Proposer une séance",
        field: nil,
        frenchBody: """
        Bonjour {name} 💛 Souhaites-tu réserver une nouvelle séance ? Je serais heureuse de t'accompagner à nouveau. Dis-moi tes disponibilités et on trouve un moment 🌸
        """,
        portugueseBody: """
        Olá {name} 💛 Gostarias de marcar uma nova sessão? Teria muito gosto em acompanhar-te de novo. Diz-me a tua disponibilidade e encontramos um momento 🌸
        """
    )
}

// MARK: - WhatsApp URL building

extension MessageTemplate {
    /// Builds a `https://wa.me/<digits>?text=<body>` URL using `URLComponents`,
    /// so emojis and newlines are percent-encoded correctly.
    ///
    /// `phone` should be the raw client phone; non-digit characters are stripped.
    /// Returns `nil` if no phone digits are available.
    static func whatsAppURL(phone: String, body: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: body)]
        return components.url
    }
}
