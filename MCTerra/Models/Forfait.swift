//
//  Forfait.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import SwiftData

/// A service package (forfait) Marta can manage from Settings: add, edit or remove.
///
/// Sessions copy the forfait's `name`, `durationMinutes` and `priceCHF` at creation
/// time (the `Seance` keeps a plain `serviceName` string, no relation), so renaming
/// or deleting a forfait never rewrites past sessions.
@Model
final class Forfait {
    /// Stable identity, mostly for future deep-linking; default `UUID()` keeps
    /// SwiftData migration lightweight.
    var uuid: UUID = UUID()
    /// Display name shown in the session picker (brand wording).
    var name: String
    /// Default duration in minutes, pre-filled when the forfait is picked.
    var durationMinutes: Int
    /// Default price in CHF, pre-filled when the forfait is picked.
    var priceCHF: Double
    /// Manual ordering in the list and the picker (lower comes first).
    var sortOrder: Int = 0
    var createdAt: Date
    /// Date de dernière modification, exposée pour préparer la sync v2. Défaut
    /// `.now` pour garder une migration SwiftData légère sur les forfaits existants.
    /// NB : on ne la bumpe pas à chaque mutation dans l'app (boulot de la sync v2,
    /// hors scope) ; ici on veut juste que la colonne existe et soit exportée/importée.
    var updatedAt: Date = Date.now

    init(
        uuid: UUID = UUID(),
        name: String,
        durationMinutes: Int,
        priceCHF: Double,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.uuid = uuid
        self.name = name
        self.durationMinutes = durationMinutes
        self.priceCHF = priceCHF
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Seeds the five default forfaits the first time the app runs, so nothing
    /// breaks for an existing install: as long as at least one forfait exists we
    /// leave the user's list untouched. The defaults are read from `ServiceType`
    /// (excluding the free `.custom` case) to keep a single source of truth.
    static func seedDefaultsIfNeeded(_ context: ModelContext) {
        var descriptor = FetchDescriptor<Forfait>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }

        let presets = ServiceType.allCases.filter { !$0.isCustom }
        for (index, preset) in presets.enumerated() {
            let forfait = Forfait(
                name: preset.displayName,
                durationMinutes: preset.defaultDurationMinutes,
                priceCHF: preset.defaultPriceCHF,
                sortOrder: index
            )
            context.insert(forfait)
        }
        try? context.save()
    }
}
