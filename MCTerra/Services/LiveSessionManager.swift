//
//  LiveSessionManager.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import Foundation
import Combine
import SwiftData
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Drives the session Live Activity (lock screen + Dynamic Island).
///
/// Holds at most one current activity. A session can be *prepared*
/// (`startScheduled(for:)`, isRunning=false) so the activity shows up on the lock
/// screen with a Play button before the appointment, then *started*
/// (`markRunning()` or the lock-screen Play button) to begin the elapsed timer,
/// and finally finished (`end()`). Everything is gated behind iOS 16.2 and the
/// user's Live Activities setting; on older systems or when disabled the calls are
/// simply no-ops, and the in-app timer (`activeStart`) still works when running.
@MainActor
final class LiveSessionManager: ObservableObject {

    /// The session currently being tracked in-app, or `nil` when none is tracked.
    @Published private(set) var activeSeance: Seance?
    /// When the active session started; drives the in-app live timer. `nil` while
    /// the session is only prepared (not started yet).
    @Published private(set) var activeStart: Date?
    /// `true` once the tracked session is actually running (timer ticking),
    /// `false` while it is only prepared on the lock screen.
    @Published private(set) var isLive: Bool = false

    /// True while a session is being tracked (prepared OR running), regardless of
    /// Live Activity availability.
    var isRunning: Bool { activeSeance != nil }

    #if canImport(ActivityKit)
    /// The current Live Activity, when one was successfully requested.
    private var currentActivity: Any?
    #endif

    /// Returns true when this manager is tracking the given session.
    func isRunning(_ seance: Seance) -> Bool {
        activeSeance?.persistentModelID == seance.persistentModelID
    }

    // MARK: - Start (running)

    /// Starts tracking `seance` immediately in the running state: marks it active
    /// in-app and, when possible, requests a running Live Activity showing
    /// client / service / location / elapsed time.
    func start(for seance: Seance) {
        let now = Date.now
        activeSeance = seance
        activeStart = now
        isLive = true
        // She launched it, so drop the "start" and "did you forget?" reminders.
        NotificationService.cancelStartNudge(for: seance)
        requestActivity(for: seance, isRunning: true, startDate: now)
    }

    // MARK: - Prepare (scheduled)

    /// Prepares `seance` on the lock screen WITHOUT starting it: requests a Live
    /// Activity in the `isRunning=false` state so its Play button can later start
    /// the session without opening the app. The in-app timer stays idle until then.
    func startScheduled(for seance: Seance) {
        activeSeance = seance
        activeStart = nil
        isLive = false
        // Use a placeholder startDate; the timer is only shown once running.
        requestActivity(for: seance, isRunning: false, startDate: .now)
    }

    /// Flips an already-prepared session into the running state (in-app + Live
    /// Activity). Used when the user taps "Démarrer" in-app after preparing.
    func markRunning() {
        guard activeSeance != nil else { return }
        let now = Date.now
        activeStart = now
        isLive = true

        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *),
              let activity = currentActivity as? Activity<SessionActivityAttributes> else { return }
        let state = SessionActivityAttributes.ContentState(isRunning: true, startDate: now)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
        #endif
    }

    // MARK: - Activity request helper

    /// Requests a Live Activity for `seance` in the given state, storing it as the
    /// current activity. No-op (beyond in-app state) when unavailable or disabled.
    private func requestActivity(for seance: Seance, isRunning: Bool, startDate: Date) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SessionActivityAttributes(
            seanceUUID: seance.uuid.uuidString,
            clientName: seance.client?.name ?? "",
            serviceName: seance.serviceName,
            location: seance.location
        )
        let state = SessionActivityAttributes.ContentState(
            isRunning: isRunning,
            startDate: startDate
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            currentActivity = activity
        } catch {
            // Non-fatal: the in-app timer still runs even if the system refuses
            // (e.g. too many activities, low-power mode).
            currentActivity = nil
        }
        #endif
    }

    // MARK: - Sync with the system activity (lock-screen ↔ app)

    #if canImport(ActivityKit)
    /// The live system activity for `seance`, matched by its embedded uuid.
    @available(iOS 16.2, *)
    private func systemActivity(for seance: Seance) -> Activity<SessionActivityAttributes>? {
        Activity<SessionActivityAttributes>.activities.first {
            $0.attributes.seanceUUID == seance.uuid.uuidString
        }
    }
    #endif

    /// Reads the current system Live Activity for `seance` and mirrors its state
    /// in-app, so the detail screen reflects a session that was started or stopped
    /// from the lock screen. No activity → clears tracking for this session.
    func sync(with seance: Seance) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard let activity = systemActivity(for: seance) else {
            if isRunning(seance) { clearState() }
            return
        }
        currentActivity = activity
        activeSeance = seance
        apply(activity.content.state)
        #endif
    }

    /// Streams live updates from `seance`'s system activity while the caller (the
    /// detail screen) is on-screen, so starting/stopping from the lock screen is
    /// reflected instantly. Returns when the activity ends or the task is cancelled.
    func observe(_ seance: Seance) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), let activity = systemActivity(for: seance) else { return }
        currentActivity = activity
        activeSeance = seance
        apply(activity.content.state)
        for await content in activity.contentUpdates {
            apply(content.state)
        }
        // The stream ends when the activity is dismissed (e.g. lock-screen Stop).
        if isRunning(seance) { clearState() }
        #endif
    }

    #if canImport(ActivityKit)
    /// Mirrors a content state into the published in-app flags.
    @available(iOS 16.2, *)
    private func apply(_ state: SessionActivityAttributes.ContentState) {
        isLive = state.isRunning
        activeStart = state.isRunning ? state.startDate : nil
    }
    #endif

    /// Clears all in-app tracking flags (without touching the system activity).
    private func clearState() {
        activeSeance = nil
        activeStart = nil
        isLive = false
        #if canImport(ActivityKit)
        currentActivity = nil
        #endif
    }

    // MARK: - End

    /// Ends the Live Activity and clears the in-app tracking state.
    func end() async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *),
           let activity = currentActivity as? Activity<SessionActivityAttributes> {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #endif

        activeSeance = nil
        activeStart = nil
        isLive = false
    }
}
