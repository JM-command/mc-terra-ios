//
//  PushConfig.example.swift
//  MCTerra
//
//  Modèle de configuration : copier ce fichier en `PushConfig.swift` (gitignoré)
//  et remplacer les placeholders par les vraies valeurs.
//

import Foundation

/// Connection details for the push-to-start server (auto-starts the session Live
/// Activity at its scheduled time). Fill these in after deploying `PushServer/`.
enum PushConfig {
    /// HTTPS base URL of the push server, no trailing slash.
    static let baseURL = "https://votre-domaine.example/push"

    /// Shared app token (matches APP_TOKEN on the server).
    static let appToken = "VOTRE_APP_TOKEN"

    static var syncURL: URL { URL(string: baseURL + "/sync")! }

    /// True once the placeholders above have been replaced with real values.
    static var isConfigured: Bool {
        !baseURL.contains("votre-domaine") && !appToken.hasPrefix("VOTRE")
    }
}
