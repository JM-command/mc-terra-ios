//
//  Note.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import Foundation
import SwiftData

/// Une note horodatée rattachée à un client. Marta en saisit à la main, et l'IA
/// peut en créer via l'outil `add_client_note`. Chaque note garde sa date de
/// création (immuable) et sa date de dernière modification, plus l'auteur.
///
/// On garde le champ `notes: String` du `Client` pour la compatibilité ; ces
/// `Note` sont le nouveau système riche (liste + éditeur plein écran).
@Model
final class Note {
    /// Identité stable, indépendante de `persistentModelID`. Défaut `UUID()` pour
    /// garder une migration SwiftData légère.
    var uuid: UUID = UUID()
    /// Le texte libre de la note.
    var text: String
    /// Date de création (sert au tri de la liste, du plus récent au plus ancien).
    var createdAt: Date
    /// Date de dernière modification (mise à jour à chaque édition).
    var updatedAt: Date
    /// "marta" (saisie manuelle) ou "ia" (créée par l'assistant).
    var author: String

    /// Client propriétaire de la note. La relation inverse est déclarée côté `Client`.
    var client: Client?

    init(
        uuid: UUID = UUID(),
        text: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        author: String = "marta",
        client: Client? = nil
    ) {
        self.uuid = uuid
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.client = client
    }
}

/// Auteurs possibles d'une note, avec un libellé et une couleur d'affichage.
enum NoteAuthor: String {
    case marta
    case ia

    /// Construit depuis la valeur stockée, avec repli sur `.marta`.
    init(stored: String) {
        self = NoteAuthor(rawValue: stored) ?? .marta
    }

    var displayName: String {
        switch self {
        case .marta: return "Marta"
        case .ia: return "IA"
        }
    }
}
