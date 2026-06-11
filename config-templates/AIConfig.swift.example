//
//  AIConfig.example.swift
//  MCTerra
//
//  Modèle de configuration : copier ce fichier en `AIConfig.swift` (gitignoré)
//  et remplacer les placeholders par les vraies valeurs.
//

import Foundation

/// Connection details for the AI command bar.
///
/// The app never holds the real Anthropic API key. It talks to a small
/// Cloudflare Worker proxy that keeps the key server-side and only relays
/// requests carrying the shared `appToken`. To rotate the token, run
/// `wrangler secret put APP_TOKEN` on the worker and update it here.
enum AIConfig {
    /// Base URL of the proxy worker (no trailing slash).
    static let proxyBaseURL = "https://VOTRE-WORKER.workers.dev"

    /// Shared app token sent as `x-app-token`. Gates access to the proxy.
    /// Not a real secret (it ships in the binary) — it just stops random
    /// internet traffic from using the worker. The real key stays on the server.
    static let appToken = "VOTRE_APP_TOKEN"

    /// Model used for the command bar. Sonnet for reliable tool-calling;
    /// bump to Haiku (`claude-haiku-4-5-20251001`) if cost/speed ever matters.
    static let model = "claude-sonnet-4-6"

    /// Cap on tokens per reply. Commands are short, so this is plenty.
    static let maxTokens = 1024

    /// Full endpoint the app POSTs to.
    static var messagesURL: URL { URL(string: proxyBaseURL + "/v1/messages")! }
}
