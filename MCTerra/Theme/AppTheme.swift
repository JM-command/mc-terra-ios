//
//  AppTheme.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

/// The three theme options the user can pick in Settings.
/// It is a `String` enum so it can be stored with @AppStorage.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Label shown in the picker. LocalizedStringResource so it goes
    /// through the String Catalog (FR/PT).
    var label: LocalizedStringResource {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    /// `nil` follows the system; otherwise forces light or dark.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
