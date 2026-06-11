//
//  Seance.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftData
import SwiftUI

/// A single session (séance) booked for a client, stored locally with SwiftData.
@Model
final class Seance {
    /// Stable identity shared across processes (app ↔ widget) and embedded in
    /// deep-link URLs (`mcterra://seance/<uuid>`). Distinct from `persistentModelID`
    /// (which isn't a stable string across processes) and never named `id` to avoid
    /// clashing with the `Identifiable` conformance `@Model` synthesizes. Default
    /// `UUID()` keeps SwiftData migration lightweight for sessions created before
    /// this field existed.
    var uuid: UUID = UUID()
    /// When the session takes place.
    var date: Date
    /// The service/forfait name (e.g. "Thérapie Émotionnelle" or a custom label).
    var serviceName: String
    /// Duration in minutes.
    var durationMinutes: Int
    /// Price in CHF.
    var priceCHF: Double
    /// Free-text note attached to this session. Doubles as the session summary/follow-up.
    var note: String
    /// Lifecycle status: "planifiee" (editable, deletable) or "terminee" (locked, only `note` editable).
    var status: String = "planifiee"
    /// Payment method recorded when the session is finished: "twint"/"carte"/"cash",
    /// or "" when not paid yet (e.g. a free discovery session). Default "" keeps
    /// SwiftData migration lightweight for sessions created before this field existed.
    var paymentMethod: String = ""
    /// Where the session happens: "cabinet"/"zoom", or "" when unset. Default ""
    /// keeps SwiftData migration lightweight for sessions created before this field.
    var location: String = ""
    /// Google Calendar event id this session was imported from, used to deduplicate
    /// imports (one Seance per event). "" means the session was created locally.
    /// Default "" keeps SwiftData migration lightweight for older sessions.
    var googleEventId: String = ""
    /// Client absent (no-show) : la séance reste en base mais n'est ni facturée
    /// (status reste "planifiee", donc hors compta) ni poussée au push-to-start.
    /// Défaut false : migration SwiftData légère et sûre pour les anciennes séances.
    var noShow: Bool = false
    var createdAt: Date
    /// Date de dernière modification, exposée pour préparer la sync v2. Défaut
    /// `.now` pour garder une migration SwiftData légère sur les séances existantes.
    /// NB : on ne la bumpe pas à chaque mutation dans l'app (boulot de la sync v2,
    /// hors scope) ; ici on veut juste que la colonne existe et soit exportée/importée.
    var updatedAt: Date = Date.now

    /// The client this session belongs to (inverse of Client.seances).
    var client: Client?

    init(
        uuid: UUID = UUID(),
        date: Date = .now,
        serviceName: String,
        durationMinutes: Int,
        priceCHF: Double,
        note: String = "",
        status: String = "planifiee",
        paymentMethod: String = "",
        location: String = "",
        googleEventId: String = "",
        noShow: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        client: Client? = nil
    ) {
        self.uuid = uuid
        self.date = date
        self.serviceName = serviceName
        self.durationMinutes = durationMinutes
        self.priceCHF = priceCHF
        self.note = note
        self.status = status
        self.paymentMethod = paymentMethod
        self.location = location
        self.googleEventId = googleEventId
        self.noShow = noShow
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.client = client
    }

    /// True when the session is finished and its core fields are locked.
    var isCompleted: Bool { status == "terminee" }
}

/// Possible lifecycle values for `Seance.status`. Kept as plain strings on the
/// model for lightweight SwiftData storage; this enum centralizes the constants.
enum SeanceStatus {
    static let planned = "planifiee"
    static let completed = "terminee"
}

/// Payment methods recorded on a finished session. Stored as the plain `rawValue`
/// string on `Seance.paymentMethod` for lightweight SwiftData storage; this enum
/// centralizes the constants, their localized labels and SF Symbol icons.
enum PaymentMethod: String, CaseIterable, Identifiable {
    case twint = "twint"
    case card = "carte"
    case cash = "cash"

    var id: String { rawValue }

    /// Localized label shown in the picker and on the session card.
    var displayName: LocalizedStringKey {
        switch self {
        case .twint: return "Twint"
        case .card: return "Carte"
        case .cash: return "Espèces"
        }
    }

    /// SF Symbol representing the payment method.
    var icon: String {
        switch self {
        case .twint: return "francsign.circle"
        case .card: return "creditcard"
        case .cash: return "banknote"
        }
    }

    /// Resolves a stored `rawValue` back to the enum, or `nil` when unpaid ("").
    init?(stored: String) {
        self.init(rawValue: stored)
    }
}

/// Where a session takes place. Stored as the plain `rawValue` string on
/// `Seance.location` for lightweight SwiftData storage; this enum centralizes
/// the constants, their localized labels and SF Symbol icons.
enum SessionLocation: String, CaseIterable, Identifiable {
    case cabinet = "cabinet"
    case online = "zoom"

    var id: String { rawValue }

    /// Localized label shown in the picker and on the session card. Kept generic
    /// ("En ligne") since the session may be on Zoom, Google Meet, etc. The raw
    /// value stays "zoom" for lightweight SwiftData migration.
    var displayName: LocalizedStringKey {
        switch self {
        case .cabinet: return "Cabinet"
        case .online: return "En ligne"
        }
    }

    /// Same label as a resource, usable from plain-string contexts like
    /// notification bodies (`String(localized:)`).
    var displayNameResource: LocalizedStringResource {
        switch self {
        case .cabinet: return "Cabinet"
        case .online: return "En ligne"
        }
    }

    /// SF Symbol representing the location.
    var icon: String {
        switch self {
        case .cabinet: return "house"
        case .online: return "video"
        }
    }

    /// Resolves a stored `rawValue` back to the enum, or `nil` when unset ("").
    init?(stored: String) {
        self.init(rawValue: stored)
    }
}
