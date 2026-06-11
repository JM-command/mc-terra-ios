//
//  MCTerraWidgetsLiveActivity.swift
//  MCTerraWidgets
//
//  Created by Jaime Coelho on 05.06.2026.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

/// Live Activity rendering a session on the lock screen and in the Dynamic Island.
///
/// Two states, driven by `context.state.isRunning`:
/// - prepared (`false`): shows client / service plus a **Play** button that starts
///   the session via `StartSessionIntent`, directly from the lock screen.
/// - running (`true`): shows a self-updating elapsed timer (`Text(timerInterval:)`,
///   no push needed) plus a red **Stop** button that ends it via `StopSessionIntent`.
struct MCTerraWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock screen / banner UI.
            LockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.6))
                .activitySystemActionForegroundColor(Color.accentColor)
                // Taper la Live Activity (hors boutons Play/Stop) ouvre la séance.
                .widgetURL(URL(string: "mcterra://seance/\(context.attributes.seanceUUID)"))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI.
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(verbatim: context.attributes.clientName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: context.attributes.locationIcon)
                            .foregroundStyle(.tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingStatus(for: context)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(verbatim: context.attributes.serviceName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        actionButton(for: context)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.locationIcon)
                    .foregroundStyle(.tint)
            } compactTrailing: {
                compactTrailing(for: context)
            } minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle")
                    .foregroundStyle(.tint)
            }
            .keylineTint(Color.accentColor)
        }
    }

    /// Expanded trailing region: the live timer when running, otherwise a hint label.
    @ViewBuilder
    private func trailingStatus(for context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        if context.state.isRunning {
            elapsedTimer(from: context.state.startDate)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tint)
        } else {
            Text("Prête")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// Compact trailing: live timer when running, Play glyph when prepared.
    @ViewBuilder
    private func compactTrailing(for context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        if context.state.isRunning {
            elapsedTimer(from: context.state.startDate)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tint)
                .frame(maxWidth: 52)
        } else {
            Image(systemName: "play.fill")
                .foregroundStyle(.tint)
        }
    }

    /// Play (prepared) / Stop (running) button. The interactive `Button(intent:)`
    /// needs iOS 17.2+; on anything older we degrade to a plain status icon.
    @ViewBuilder
    private func actionButton(for context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        if context.state.isRunning {
            // Stop opens the app on the finish screen (summary + payment).
            Link(destination: finishURL(context.attributes.seanceUUID)) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.red, in: Circle())
            }
        } else if #available(iOS 17.2, *) {
            Button(intent: StartSessionIntent()) {
                Label("Démarrer", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(Color.accentColor)
            .buttonStyle(.borderedProminent)
        } else {
            Image(systemName: "play.fill")
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - Lock screen view

/// Split out to keep the `ActivityConfiguration` closure light for the compiler.
private struct LockScreenView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Logo MCTerra (variante couleur en clair, blanche en sombre via
            // l'asset AppLogo). Remplace l'ancienne icône calendrier SF Symbol.
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: context.attributes.clientName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: context.attributes.serviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            trailing
        }
        .padding()
    }

    /// Running: elapsed timer + Stop button. Prepared: Play button.
    @ViewBuilder
    private var trailing: some View {
        if context.state.isRunning {
            HStack(spacing: 10) {
                elapsedTimer(from: context.state.startDate)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
                lockScreenButton(running: true)
            }
        } else {
            lockScreenButton(running: false)
        }
    }

    /// Play / Stop button. `Button(intent:)` requires iOS 17.2+; older systems
    /// just show a non-interactive status glyph.
    @ViewBuilder
    private func lockScreenButton(running: Bool) -> some View {
        if running {
            // Stop opens the app on the finish screen (summary + payment), which
            // can't be filled from the lock screen.
            Link(destination: finishURL(context.attributes.seanceUUID)) {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.red, in: Circle())
            }
        } else if #available(iOS 17.2, *) {
            Button(intent: StartSessionIntent()) {
                Image(systemName: "play.fill")
                    .font(.title3)
            }
            .tint(Color.accentColor)
            .buttonStyle(.borderedProminent)
        } else {
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - Shared timer helper

/// Self-updating elapsed-time label counting up from `start`.
@ViewBuilder
private func elapsedTimer(from start: Date) -> some View {
    Text(timerInterval: start...Date.distantFuture, countsDown: false)
        .multilineTextAlignment(.trailing)
}

/// Deep link that opens the app on the session's finish flow (summary + payment),
/// which can't be filled from the lock screen. Used by the Stop control.
private func finishURL(_ uuid: String) -> URL {
    URL(string: "mcterra://seance/\(uuid)?finish=1") ?? URL(string: "mcterra://seance")!
}

// MARK: - Previews

extension SessionActivityAttributes {
    fileprivate static var preview: SessionActivityAttributes {
        SessionActivityAttributes(
            seanceUUID: "",
            clientName: "Marta Coelho",
            serviceName: "Thérapie Émotionnelle",
            location: "cabinet"
        )
    }
}

extension SessionActivityAttributes.ContentState {
    fileprivate static var prepared: SessionActivityAttributes.ContentState {
        SessionActivityAttributes.ContentState(isRunning: false, startDate: .now)
    }

    fileprivate static var running: SessionActivityAttributes.ContentState {
        SessionActivityAttributes.ContentState(isRunning: true, startDate: .now)
    }
}

#Preview("Notification", as: .content, using: SessionActivityAttributes.preview) {
    MCTerraWidgetsLiveActivity()
} contentStates: {
    SessionActivityAttributes.ContentState.prepared
    SessionActivityAttributes.ContentState.running
}
