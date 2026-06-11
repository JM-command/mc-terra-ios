//
//  DeepLinkRouter.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Shared observable that turns an incoming `mcterra://` URL into a target route.
//  The app injects one instance as an `environmentObject`; `MCTerraApp` writes the
//  parsed route on `.onOpenURL`, and `ContentView` observes it to present the
//  matching screen in a full-screen cover. Keeping the parsing here means the URL
//  scheme lives in one place, in step with the widgets' `WidgetDeepLink` builder.

import Foundation
import Combine

/// A target screen requested by a `mcterra://` deep link.
///
/// URL shape (host = destination, first path component = identifier):
/// - `mcterra://seance/<uuid>` → a specific session.
/// - `mcterra://client/<uuid>` → a specific client.
/// - `mcterra://compta`        → the accounting dashboard (no identifier).
enum DeepLinkRoute: Equatable, Identifiable {
    case seance(UUID)
    /// A session opened straight into its finish flow (summary + payment), used by
    /// the Live Activity Stop control (`mcterra://seance/<uuid>?finish=1`).
    case seanceFinish(UUID)
    case client(UUID)
    case compta

    /// Stable identity so the route can drive a SwiftUI `.fullScreenCover(item:)`.
    var id: String {
        switch self {
        case .seance(let uuid): return "seance-\(uuid.uuidString)"
        case .seanceFinish(let uuid): return "seance-finish-\(uuid.uuidString)"
        case .client(let uuid): return "client-\(uuid.uuidString)"
        case .compta: return "compta"
        }
    }
}

/// Holds the route most recently requested by a deep link. `ContentView` clears it
/// when the presented cover is dismissed.
final class DeepLinkRouter: ObservableObject {
    /// The current target, or `nil` when nothing is being presented.
    @Published var route: DeepLinkRoute?

    /// Parses a `mcterra://` URL and, when it matches a known destination, stores
    /// the route. Returns `true` when the URL was handled (so callers know not to
    /// pass it on to other handlers). Malformed or unknown URLs are ignored.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "mcterra" else { return false }

        // `host` is the destination; the first path segment (if any) is the uuid.
        let destination = url.host
        let identifier = url.pathComponents.first { $0 != "/" }
        // `?finish=1` opens a session straight into its finish flow.
        let wantsFinish = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "finish" && $0.value == "1" } ?? false

        switch destination {
        case "seance":
            guard let identifier, let uuid = UUID(uuidString: identifier) else { return false }
            route = wantsFinish ? .seanceFinish(uuid) : .seance(uuid)
            return true
        case "client":
            guard let identifier, let uuid = UUID(uuidString: identifier) else { return false }
            route = .client(uuid)
            return true
        case "compta":
            route = .compta
            return true
        default:
            return false
        }
    }
}
