//
//  ServiceType.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation

/// A predefined service (forfait) Marta can pick when creating a session.
/// Duration and price pre-fill the form but stay editable. The `.custom`
/// case lets her enter a free duration and price.
enum ServiceType: String, CaseIterable, Identifiable {
    case decouverte
    case therapieEmotionnelle
    case massageHuiles
    case constellationIndividuelle
    case constellationGroupe
    case custom

    var id: String { rawValue }

    /// Display name shown in the picker. Service names stay as-is (brand wording),
    /// except "Personnalisé" which is localized.
    var displayName: String {
        switch self {
        case .decouverte: return "Séance Découverte"
        case .therapieEmotionnelle: return "Thérapie Émotionnelle"
        case .massageHuiles: return "Massage aux Huiles Essentielles"
        case .constellationIndividuelle: return "Constellation Individuelle"
        case .constellationGroupe: return "Constellation en Groupe"
        case .custom: return "Personnalisé"
        }
    }

    /// Default duration in minutes (ignored for `.custom`).
    var defaultDurationMinutes: Int {
        switch self {
        case .decouverte: return 30
        case .therapieEmotionnelle: return 60
        case .massageHuiles: return 60
        case .constellationIndividuelle: return 60
        case .constellationGroupe: return 180
        case .custom: return 60
        }
    }

    /// Default price in CHF (ignored for `.custom`).
    var defaultPriceCHF: Double {
        switch self {
        case .decouverte: return 0
        case .therapieEmotionnelle: return 80
        case .massageHuiles: return 120
        case .constellationIndividuelle: return 80
        case .constellationGroupe: return 120
        case .custom: return 0
        }
    }

    /// True when the user must type duration and price themselves.
    var isCustom: Bool { self == .custom }
}
