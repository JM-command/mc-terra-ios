//
//  DataImportService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 11.06.2026.
//

import Foundation
import SwiftData

/// Service d'import miroir de `DataExportService` : relit un fichier JSON produit
/// par l'export et le ré-applique dans SwiftData.
///
/// On reste 100% local. L'import est un UPSERT PAR UUID, idempotent : réimporter le
/// même fichier ne crée jamais de doublon (chaque entité est retrouvée par son
/// `uuid`, mise à jour si présente, insérée sinon). On réutilise les mêmes structs
/// Codable que l'export (`ExportPayload`/`ExportClient`/...), donc un seul format.
///
/// Rétro-compatibilité : `schemaVersion` 1 ET 2 sont acceptés. Les champs ajoutés
/// en v2 (email, address, updatedAt, notes) sont optionnels au décodage ; les
/// accesseurs `*OrDefault`/`*OrNow`/`notesOrEmpty` des structs d'export fournissent
/// les valeurs de repli (email/adresse = "", updatedAt = .now, notes = []).
enum DataImportService {

    /// Erreurs possibles de l'import, pour gérer l'échec sans crash côté UI.
    enum ImportError: LocalizedError {
        case fileUnreadable(underlying: Error)
        case decodeFailed(underlying: Error)
        case saveFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .fileUnreadable:
                return String(localized: "Impossible de lire le fichier sélectionné.")
            case .decodeFailed:
                return String(localized: "Le fichier n'a pas le bon format (JSON MCTerra invalide).")
            case .saveFailed:
                return String(localized: "Impossible d'enregistrer les données importées.")
            }
        }
    }

    /// Bilan de l'import, affiché à l'utilisateur (nb ajoutés vs mis à jour par type).
    struct ImportSummary {
        var clientsInserted = 0
        var clientsUpdated = 0
        var seancesInserted = 0
        var seancesUpdated = 0
        var forfaitsInserted = 0
        var forfaitsUpdated = 0
        var notesInserted = 0
        var notesUpdated = 0
    }

    /// Lit le fichier `url`, décode le JSON puis applique l'upsert dans `context`.
    /// Retourne un `ImportSummary`, ou lève une `ImportError` en cas d'échec.
    static func importAll(from url: URL, context: ModelContext) throws -> ImportSummary {
        // 1. Lecture du fichier.
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileUnreadable(underlying: error)
        }

        // 2. Décodage (mêmes structs que l'export, dates iso8601, champs v2 optionnels).
        let payload: ExportPayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(ExportPayload.self, from: data)
        } catch {
            throw ImportError.decodeFailed(underlying: error)
        }

        var summary = ImportSummary()

        // 3. Upsert dans l'ordre des dépendances : clients, puis forfaits, puis
        // séances et notes (qui se relient au client via `clientUuid`).
        var clientsByUuid: [UUID: Client] = [:]

        // 3a. Clients.
        for exported in payload.clients {
            if let existing = fetchClient(uuid: exported.uuid, context: context) {
                existing.name = exported.name
                existing.phone = exported.phone
                existing.email = exported.emailOrDefault
                existing.address = exported.addressOrDefault
                existing.language = exported.language
                existing.notes = exported.notes
                existing.createdAt = exported.createdAt
                existing.updatedAt = exported.updatedAtOrNow
                clientsByUuid[exported.uuid] = existing
                summary.clientsUpdated += 1
            } else {
                let client = Client(
                    uuid: exported.uuid,
                    name: exported.name,
                    phone: exported.phone,
                    email: exported.emailOrDefault,
                    address: exported.addressOrDefault,
                    language: exported.language,
                    notes: exported.notes,
                    createdAt: exported.createdAt,
                    updatedAt: exported.updatedAtOrNow
                )
                context.insert(client)
                clientsByUuid[exported.uuid] = client
                summary.clientsInserted += 1
            }
        }

        // 3b. Forfaits.
        for exported in payload.forfaits {
            if let existing = fetchForfait(uuid: exported.uuid, context: context) {
                existing.name = exported.name
                existing.durationMinutes = exported.durationMinutes
                existing.priceCHF = exported.priceCHF
                existing.sortOrder = exported.sortOrder
                existing.createdAt = exported.createdAt
                existing.updatedAt = exported.updatedAtOrNow
                summary.forfaitsUpdated += 1
            } else {
                let forfait = Forfait(
                    uuid: exported.uuid,
                    name: exported.name,
                    durationMinutes: exported.durationMinutes,
                    priceCHF: exported.priceCHF,
                    sortOrder: exported.sortOrder,
                    createdAt: exported.createdAt,
                    updatedAt: exported.updatedAtOrNow
                )
                context.insert(forfait)
                summary.forfaitsInserted += 1
            }
        }

        // 3c. Séances (reliées au client via `clientUuid`).
        for exported in payload.seances {
            let client = resolveClient(
                uuid: exported.clientUuid,
                cache: &clientsByUuid,
                context: context
            )
            if let existing = fetchSeance(uuid: exported.uuid, context: context) {
                existing.date = exported.date
                existing.serviceName = exported.serviceName
                existing.durationMinutes = exported.durationMinutes
                existing.priceCHF = exported.priceCHF
                existing.note = exported.note
                existing.status = exported.status
                existing.paymentMethod = exported.paymentMethod
                existing.location = exported.location
                existing.googleEventId = exported.googleEventId
                existing.noShow = exported.noShow
                existing.createdAt = exported.createdAt
                existing.updatedAt = exported.updatedAtOrNow
                existing.client = client
                summary.seancesUpdated += 1
            } else {
                let seance = Seance(
                    uuid: exported.uuid,
                    date: exported.date,
                    serviceName: exported.serviceName,
                    durationMinutes: exported.durationMinutes,
                    priceCHF: exported.priceCHF,
                    note: exported.note,
                    status: exported.status,
                    paymentMethod: exported.paymentMethod,
                    location: exported.location,
                    googleEventId: exported.googleEventId,
                    noShow: exported.noShow,
                    createdAt: exported.createdAt,
                    updatedAt: exported.updatedAtOrNow,
                    client: client
                )
                context.insert(seance)
                summary.seancesInserted += 1
            }
        }

        // 3d. Notes (reliées au client via `clientUuid`). Absentes des fichiers v1.
        for exported in payload.notesOrEmpty {
            let client = resolveClient(
                uuid: exported.clientUuid,
                cache: &clientsByUuid,
                context: context
            )
            if let existing = fetchNote(uuid: exported.uuid, context: context) {
                existing.text = exported.text
                existing.createdAt = exported.createdAt
                existing.updatedAt = exported.updatedAt
                existing.author = exported.author
                existing.client = client
                summary.notesUpdated += 1
            } else {
                let note = Note(
                    uuid: exported.uuid,
                    text: exported.text,
                    createdAt: exported.createdAt,
                    updatedAt: exported.updatedAt,
                    author: exported.author,
                    client: client
                )
                context.insert(note)
                summary.notesInserted += 1
            }
        }

        // 4. Sauvegarde finale.
        do {
            try context.save()
        } catch {
            throw ImportError.saveFailed(underlying: error)
        }

        return summary
    }

    // MARK: - Résolution du client lié

    /// Retrouve un `Client` par `uuid` pour relier une séance/note. Cherche d'abord
    /// dans le cache rempli à l'étape clients, sinon fait un fetch (cas d'un fichier
    /// où la note précède son client, ou d'un client déjà présent en base). Retourne
    /// nil si `uuid` est nil ou introuvable (entité orpheline, tolérée).
    private static func resolveClient(
        uuid: UUID?,
        cache: inout [UUID: Client],
        context: ModelContext
    ) -> Client? {
        guard let uuid else { return nil }
        if let cached = cache[uuid] { return cached }
        if let fetched = fetchClient(uuid: uuid, context: context) {
            cache[uuid] = fetched
            return fetched
        }
        return nil
    }

    // MARK: - Fetch par uuid (un par type)

    private static func fetchClient(uuid: UUID, context: ModelContext) -> Client? {
        var descriptor = FetchDescriptor<Client>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchForfait(uuid: UUID, context: ModelContext) -> Forfait? {
        var descriptor = FetchDescriptor<Forfait>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchSeance(uuid: UUID, context: ModelContext) -> Seance? {
        var descriptor = FetchDescriptor<Seance>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchNote(uuid: UUID, context: ModelContext) -> Note? {
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
