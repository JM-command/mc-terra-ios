//
//  PushToStartService.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//
//  Sends the app's pushToStart token + the list of upcoming sessions to the push
//  server, so it can fire an APNs "push-to-start" at each session's time and the
//  Live Activity timer appears on the lock screen on its own (iOS won't let the
//  app do that itself). The app is the source of truth: it re-syncs the full list
//  on launch, on foreground, and whenever the token rotates.
//

import Foundation
import SwiftData
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class PushToStartService {
    static let shared = PushToStartService()

    /// Latest pushToStart token (hex), or nil until ActivityKit provides one.
    private var token: String?
    private var observing = false

    /// Starts watching the pushToStart token. Each rotation re-syncs the server.
    func startObserving() {
        #if canImport(ActivityKit)
        guard #available(iOS 17.2, *), !observing, PushConfig.isConfigured else { return }
        observing = true
        Task {
            for await data in Activity<SessionActivityAttributes>.pushToStartTokenUpdates {
                token = data.map { String(format: "%02x", $0) }.joined()
                sync(using: SharedModelContainer.shared.mainContext)
            }
        }
        #endif
    }

    /// Pushes the current token + all upcoming planned sessions to the server.
    func sync(using context: ModelContext) {
        guard PushConfig.isConfigured, let token else { return }
        let now = Date()
        let all = (try? context.fetch(FetchDescriptor<Seance>())) ?? []
        let upcoming = all
            .filter { $0.status == SeanceStatus.planned && $0.date >= now && !$0.noShow }
            .sorted { $0.date < $1.date }
            .prefix(50)

        let schedules = upcoming.map(schedulePayload(for:))
        post(token: token, schedules: Array(schedules))
    }

    // MARK: - Payload

    private func schedulePayload(for seance: Seance) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let attributes: [String: Any] = [
            "seanceUUID": seance.uuid.uuidString,
            "clientName": seance.client?.name ?? "",
            "serviceName": seance.serviceName,
            "location": seance.location
        ]
        // startDate as Unix seconds. If the timer shows the wrong time, this is the
        // format to revisit (see Milestone-PushToStart.md, piège n°1).
        let contentState: [String: Any] = [
            "isRunning": true,
            "startDate": seance.date.timeIntervalSince1970
        ]
        let alert: [String: Any] = [
            "title": "Séance",
            "body": seance.client?.name ?? seance.serviceName
        ]
        return [
            "id": seance.uuid.uuidString,
            "fireAt": formatter.string(from: seance.date),
            "attributes": attributes,
            "contentState": contentState,
            "alert": alert
        ]
    }

    private func post(token: String, schedules: [[String: Any]]) {
        let body: [String: Any] = ["token": token, "schedules": schedules]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: PushConfig.syncURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(PushConfig.appToken, forHTTPHeaderField: "x-app-token")
        request.httpBody = data
        Task { _ = try? await URLSession.shared.data(for: request) }
    }
}
