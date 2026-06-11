//
//  Client.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftData

/// A client, stored locally on the device with SwiftData.
@Model
final class Client {
    /// Stable identity shared across processes (app ↔ widget) and embedded in
    /// deep-link URLs (`mcterra://client/<uuid>`). Distinct from `persistentModelID`
    /// and never named `id` to avoid clashing with the `Identifiable` conformance
    /// `@Model` synthesizes. Default `UUID()` keeps SwiftData migration lightweight
    /// for clients created before this field existed.
    var uuid: UUID = UUID()
    var name: String
    var phone: String
    /// Adresse e-mail du client (vide si non renseignée). Défaut "" pour garder
    /// une migration SwiftData légère sur les clients existants.
    var email: String = ""
    /// Adresse postale libre du client (vide si non renseignée). Défaut "".
    var address: String = ""
    /// "fr" or "pt" — the language this client speaks.
    var language: String
    /// Free-text summary shown in the client's "Infos" tab (for now).
    var notes: String
    var createdAt: Date
    /// Date de dernière modification, exposée pour préparer la sync v2. Défaut
    /// `.now` pour garder une migration SwiftData légère sur les clients existants.
    /// NB : on ne la bumpe pas à chaque mutation dans l'app (boulot de la sync v2,
    /// hors scope) ; ici on veut juste que la colonne existe et soit exportée/importée.
    var updatedAt: Date = Date.now

    /// Sessions booked for this client. Deleting the client deletes its sessions.
    @Relationship(deleteRule: .cascade, inverse: \Seance.client)
    var seances: [Seance] = []

    /// Notes horodatées du client (système riche). Supprimer le client supprime
    /// ses notes. La relation inverse est déclarée côté `Note.client`.
    @Relationship(deleteRule: .cascade, inverse: \Note.client)
    var noteEntries: [Note] = []

    init(
        uuid: UUID = UUID(),
        name: String,
        phone: String = "",
        email: String = "",
        address: String = "",
        language: String = "fr",
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.language = language
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
