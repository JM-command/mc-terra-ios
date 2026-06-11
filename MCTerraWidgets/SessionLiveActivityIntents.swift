//
//  SessionLiveActivityIntents.swift
//  MCTerra / MCTerraWidgetsExtension
//
//  Created by Jaime Coelho on 05.06.2026.
//

// ⚠️ This file MUST belong to BOTH targets: MCTerra AND MCTerraWidgetsExtension.
// The intents are *declared* in the widget (so `Button(intent:)` can reference
// them) and *resolved* in the app process at runtime. In Xcode, select this file
// and check BOTH Target Membership boxes in the File Inspector. The project's
// pbxproj already wires this up via a PBXFileSystemSynchronizedBuildFileExceptionSet
// (same mechanism as SessionActivityAttributes.swift) — if you regenerate the
// project, make sure that exception is preserved or the build will fail.

import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

// LiveActivityIntent (interactive Live Activity buttons) requires iOS 17.2+.
// The app deploys to iOS 26.2, so these are always available at runtime, but we
// keep the explicit availability so the intent contract stays honest.

/// Starts the currently-prepared session straight from the Live Activity:
/// flips its `ContentState` to running and (re)sets the elapsed-timer origin to now.
@available(iOS 17.2, *)
struct StartSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Démarrer la séance"
    static var description = IntentDescription("Démarre la séance depuis l'écran verrouillé.")

    /// Runs in the app's process; updates the current activity's content state.
    func perform() async throws -> some IntentResult {
        #if canImport(ActivityKit)
        if let activity = Activity<SessionActivityAttributes>.activities.first {
            let state = SessionActivityAttributes.ContentState(
                isRunning: true,
                startDate: .now
            )
            await activity.update(.init(state: state, staleDate: nil))
            // Ouvre la séance dans l'app après l'avoir démarrée depuis l'écran
            // verrouillé : on rediffuse le deep link (Name partagée via
            // SessionActivityAttributes.swift) que le `DeepLinkRouter` route.
            let uuid = activity.attributes.seanceUUID
            if let url = URL(string: "mcterra://seance/\(uuid)") {
                await MainActor.run {
                    NotificationCenter.default.post(name: .mcterraDeepLink, object: url)
                }
            }
        }
        #endif
        return .result()
    }
}

/// Ends the current session straight from the Live Activity, dismissing it.
@available(iOS 17.2, *)
struct StopSessionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Terminer la séance"
    static var description = IntentDescription("Termine la séance depuis l'écran verrouillé.")

    /// Runs in the app's process; ends the current activity immediately.
    func perform() async throws -> some IntentResult {
        #if canImport(ActivityKit)
        if let activity = Activity<SessionActivityAttributes>.activities.first {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
        return .result()
    }
}
