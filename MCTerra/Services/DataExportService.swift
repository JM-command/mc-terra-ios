//
//  DataExportService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import Foundation
import SwiftData

/// Service d'export de toutes les données locales (Client, Seance, Forfait, Note)
/// vers un fichier JSON lisible, pour backup/migration.
///
/// On reste 100% local : ce service lit le schéma actuel via un `ModelContext`,
/// produit un dictionnaire `{ clients[], seances[], forfaits[], notes[] }` (chaque
/// entité avec ses champs principaux + son `uuid`, les séances et notes gardant le
/// `clientUuid` pour relier au client), l'écrit dans un fichier temporaire et
/// retourne l'URL, prête à être partagée via `ShareLink`/`UIActivityViewController`.
///
/// Le format est versionné via `schemaVersion` (v2 ajoute email/adresse client,
/// `updatedAt` sur chaque entité, et le tableau `notes[]`). `DataImportService`
/// réutilise les mêmes structs Codable pour un import miroir (upsert par uuid).
enum DataExportService {

    /// Erreurs possibles de l'export, pour gérer l'échec sans crash côté UI.
    enum ExportError: LocalizedError {
        case encodingFailed
        case writeFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return String(localized: "Impossible d'encoder les données en JSON.")
            case .writeFailed:
                return String(localized: "Impossible d'écrire le fichier d'export.")
            }
        }
    }

    /// Lit toutes les données via le `ModelContext` et écrit le JSON dans un
    /// fichier temporaire. Retourne l'URL du fichier (à partager), ou lève une
    /// `ExportError` en cas d'échec.
    static func exportAll(context: ModelContext) throws -> URL {
        let payload = buildPayload(context: context)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw ExportError.encodingFailed
        }

        let url = temporaryFileURL()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
        return url
    }

    // MARK: - Construction du contenu

    /// Lit chaque entité du schéma et assemble le payload exportable. Les fetch
    /// échouant retournent un tableau vide (export partiel plutôt que crash).
    private static func buildPayload(context: ModelContext) -> ExportPayload {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let seances = (try? context.fetch(FetchDescriptor<Seance>())) ?? []
        let forfaits = (try? context.fetch(FetchDescriptor<Forfait>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []

        return ExportPayload(
            exportedAt: .now,
            schemaVersion: 2,
            clients: clients.map(ExportClient.init),
            seances: seances.map(ExportSeance.init),
            forfaits: forfaits.map(ExportForfait.init),
            notes: notes.map(ExportNote.init)
        )
    }

    /// URL d'un fichier temporaire nommé `MCTerra-export-<date>.json`.
    private static func temporaryFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: .now)
        let name = "MCTerra-export-\(stamp).json"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}

// MARK: - Modèles d'export (Codable, miroir léger du schéma)
//
// Ces structs sont `internal` (pas `private`) pour être réutilisées telles quelles
// par `DataImportService` : un seul jeu de structs sert à l'encodage (export) et au
// décodage (import). Les champs ajoutés en v2 (email, address, updatedAt, notes)
// sont optionnels : un fichier v1 (qui ne les contient pas) décode `nil`, et chaque
// struct expose un accesseur `*OrDefault` fournissant la valeur de repli. À l'export
// on les écrit toujours non-nil (le schéma courant les possède tous).

/// Enveloppe racine du JSON exporté.
struct ExportPayload: Codable {
    let exportedAt: Date
    let schemaVersion: Int
    let clients: [ExportClient]
    let seances: [ExportSeance]
    let forfaits: [ExportForfait]
    /// Ajouté en v2 : absent (nil) dans les fichiers v1.
    let notes: [ExportNote]?

    /// Notes du fichier, ou tableau vide pour un fichier v1 sans `notes`.
    var notesOrEmpty: [ExportNote] { notes ?? [] }
}

struct ExportClient: Codable {
    let uuid: UUID
    let name: String
    let phone: String
    /// Ajouté en v2 : nil dans les fichiers v1.
    let email: String?
    /// Ajouté en v2 : nil dans les fichiers v1.
    let address: String?
    let language: String
    let notes: String
    let createdAt: Date
    /// Ajouté en v2 : nil dans les fichiers v1.
    let updatedAt: Date?

    /// Repli "" si le fichier v1 n'a pas d'email.
    var emailOrDefault: String { email ?? "" }
    /// Repli "" si le fichier v1 n'a pas d'adresse.
    var addressOrDefault: String { address ?? "" }
    /// Repli `.now` si le fichier v1 n'a pas d'`updatedAt`.
    var updatedAtOrNow: Date { updatedAt ?? .now }

    init(_ client: Client) {
        self.uuid = client.uuid
        self.name = client.name
        self.phone = client.phone
        self.email = client.email
        self.address = client.address
        self.language = client.language
        self.notes = client.notes
        self.createdAt = client.createdAt
        self.updatedAt = client.updatedAt
    }
}

struct ExportSeance: Codable {
    let uuid: UUID
    /// `uuid` du client lié, pour relier séances ↔ clients (nil si sans client).
    let clientUuid: UUID?
    let date: Date
    let serviceName: String
    let durationMinutes: Int
    let priceCHF: Double
    let note: String
    let status: String
    let paymentMethod: String
    let location: String
    let googleEventId: String
    let noShow: Bool
    let createdAt: Date
    /// Ajouté en v2 : nil dans les fichiers v1.
    let updatedAt: Date?

    /// Repli `.now` si le fichier v1 n'a pas d'`updatedAt`.
    var updatedAtOrNow: Date { updatedAt ?? .now }

    init(_ seance: Seance) {
        self.uuid = seance.uuid
        self.clientUuid = seance.client?.uuid
        self.date = seance.date
        self.serviceName = seance.serviceName
        self.durationMinutes = seance.durationMinutes
        self.priceCHF = seance.priceCHF
        self.note = seance.note
        self.status = seance.status
        self.paymentMethod = seance.paymentMethod
        self.location = seance.location
        self.googleEventId = seance.googleEventId
        self.noShow = seance.noShow
        self.createdAt = seance.createdAt
        self.updatedAt = seance.updatedAt
    }
}

struct ExportForfait: Codable {
    let uuid: UUID
    let name: String
    let durationMinutes: Int
    let priceCHF: Double
    let sortOrder: Int
    let createdAt: Date
    /// Ajouté en v2 : nil dans les fichiers v1.
    let updatedAt: Date?

    /// Repli `.now` si le fichier v1 n'a pas d'`updatedAt`.
    var updatedAtOrNow: Date { updatedAt ?? .now }

    init(_ forfait: Forfait) {
        self.uuid = forfait.uuid
        self.name = forfait.name
        self.durationMinutes = forfait.durationMinutes
        self.priceCHF = forfait.priceCHF
        self.sortOrder = forfait.sortOrder
        self.createdAt = forfait.createdAt
        self.updatedAt = forfait.updatedAt
    }
}

/// Note horodatée exportée (système riche). Reliée au client via `clientUuid`.
/// Toute la struct est nouvelle en v2 ; un fichier v1 n'a tout simplement pas de
/// tableau `notes[]` (voir `ExportPayload.notesOrEmpty`).
struct ExportNote: Codable {
    let uuid: UUID
    /// `uuid` du client propriétaire, pour relier note ↔ client (nil si orpheline).
    let clientUuid: UUID?
    let text: String
    let createdAt: Date
    let updatedAt: Date
    let author: String

    init(_ note: Note) {
        self.uuid = note.uuid
        self.clientUuid = note.client?.uuid
        self.text = note.text
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
        self.author = note.author
    }
}
