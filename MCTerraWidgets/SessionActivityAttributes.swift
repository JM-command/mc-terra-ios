//
//  SessionActivityAttributes.swift
//  MCTerra / MCTerraWidgetsExtension
//
//  Created by Jaime Coelho on 05.06.2026.
//

// ⚠️ This file MUST belong to BOTH targets: MCTerra AND MCTerraWidgetsExtension.
// In Xcode, select this file and check both Target Membership boxes in the
// File Inspector. The project won't build until then.

import ActivityKit
import Foundation

/// Shared Live Activity attributes describing a session.
///
/// The fixed (non-changing) properties — client, service, location — are set once
/// when the activity is requested. The dynamic `ContentState` carries `isRunning`
/// and `startDate`: a "prepared" activity (isRunning=false) shows the info plus a
/// Play button on the lock screen, and a "running" one (isRunning=true) shows the
/// live, self-updating elapsed timer plus a Stop button.
struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// `false` while the session is only prepared (not started yet), `true`
        /// once it is running. Drives which button (Play vs Stop) is shown.
        var isRunning: Bool
        /// When the session started; the timer counts up from here once running.
        var startDate: Date
    }

    /// The session's stable `uuid` string, so the app can match this activity back
    /// to a specific `Seance` (e.g. when a session is started from the lock screen
    /// and the in-app detail screen needs to reflect it).
    let seanceUUID: String
    /// Client display name (e.g. "Marta Coelho").
    let clientName: String
    /// Service/forfait name (e.g. "Thérapie Émotionnelle").
    let serviceName: String
    /// Raw `SessionLocation` value ("cabinet"/"zoom"), or "" when unset.
    let location: String
}

extension Notification.Name {
    /// Diffusée dans le process de l'app quand un deep link `mcterra://` doit être
    /// routé (depuis le delegate de notifications ou un intent de Live Activity).
    /// L'objet associé est l'`URL` à passer au `DeepLinkRouter`. Déclarée ici car
    /// ce fichier appartient aux DEUX targets (app + widget), donc le symbole est
    /// partagé entre les intents (widget) et le routeur (app).
    static let mcterraDeepLink = Notification.Name("ch.irixiagroup.MCTerra.deepLink")
}

extension SessionActivityAttributes {
    /// SF Symbol for the stored `location` string. Kept here (not on the app-only
    /// `SessionLocation` enum) so the widget target can resolve the icon too.
    var locationIcon: String {
        switch location {
        case "cabinet": return "house"
        case "zoom": return "video"
        default: return "calendar"
        }
    }
}
