//
//  GoogleCalendarSection.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import LocalAuthentication

/// Settings section to connect Google Agenda, pick a calendar, and import its
/// events into the local agenda (read-only, Phase A).
struct GoogleCalendarSection: View {
    @EnvironmentObject private var google: GoogleCalendarService
    @Environment(\.modelContext) private var modelContext

    // Persisted id of the calendar the user imports from.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""

    @State private var calendars: [CalendarOption] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    // Intermediate selection bound to the Picker. We never bind the Picker
    // directly to @AppStorage: changing it requires a successful device
    // authentication before the new id is committed to @AppStorage.
    @State private var pendingCalendarId: String = ""

    var body: some View {
        Section("Google Agenda") {
            if google.isSignedIn {
                connectedContent
            } else {
                Button("Connecter Google Agenda") { connect() }
                    .disabled(isWorking)
            }

            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        // Populate the picker when the section appears already connected.
        .task {
            if google.isSignedIn && calendars.isEmpty {
                await loadCalendars()
            }
        }
    }

    // MARK: - Connected state

    @ViewBuilder
    private var connectedContent: some View {
        if let email = google.email {
            LabeledContent("Compte") { Text(verbatim: email) }
        }

        Picker("Calendrier", selection: $pendingCalendarId) {
            Text("Aucun").tag("")
            ForEach(calendars) { calendar in
                Text(verbatim: calendar.summary).tag(calendar.id)
            }
        }
        .disabled(isWorking)
        // Keep the Picker in sync with the stored id on first display
        // and whenever the committed value changes elsewhere.
        .onAppear { pendingCalendarId = googleCalendarId }
        .onChange(of: googleCalendarId) { _, newValue in
            pendingCalendarId = newValue
        }
        // A user-driven change must be confirmed by Face ID / passcode
        // before being committed to @AppStorage.
        .onChange(of: pendingCalendarId) { oldValue, newValue in
            guard newValue != googleCalendarId else { return }
            confirmCalendarChange(to: newValue, previous: oldValue)
        }

        Button("Actualiser maintenant") { refresh() }
            .disabled(isWorking || googleCalendarId.isEmpty)

        Button("Déconnecter", role: .destructive) { requestDisconnect() }
            .disabled(isWorking)
    }

    // MARK: - Actions

    private func connect() {
        guard let presenter = topViewController() else {
            errorMessage = String(localized: "Impossible d'afficher la connexion Google.")
            return
        }
        run {
            try await google.signIn(presenting: presenter)
            await loadCalendars()
        }
    }

    /// Commits a calendar change only after a successful device authentication.
    /// On failure/cancel, the Picker is reverted to the currently stored id.
    private func confirmCalendarChange(to newValue: String, previous: String) {
        authenticate(reason: String(localized: "Authentifiez-vous pour changer l'agenda connecté.")) { success in
            if success {
                googleCalendarId = newValue
            } else {
                // Revert the Picker to the stored value; never commit.
                pendingCalendarId = googleCalendarId
            }
        }
    }

    /// Disconnects Google only after a successful device authentication.
    private func requestDisconnect() {
        authenticate(reason: String(localized: "Authentifiez-vous pour déconnecter Google Agenda.")) { success in
            guard success else { return }
            google.signOut()
            calendars = []
            googleCalendarId = ""
            pendingCalendarId = ""
        }
    }

    /// Evaluates device-owner authentication (Face ID / Touch ID / passcode).
    /// If no authentication is available on the device, the action is allowed
    /// through (fail-open) rather than blocking the user. The completion always
    /// runs on the main actor.
    private func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var policyError: NSError?

        // No biometrics nor passcode configured: don't lock the user out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            completion(true)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            Task { @MainActor in
                completion(success)
            }
        }
    }

    private func refresh() {
        run {
            try await google.import(into: modelContext, calendarId: googleCalendarId)
        }
    }

    /// Loads the calendar list for the picker. Errors are surfaced, not fatal.
    private func loadCalendars() async {
        do {
            let items = try await google.listCalendars()
            calendars = items.map { CalendarOption(id: $0.id, summary: $0.summary) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Runs an async task with the busy flag and unified error handling.
    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// A pickable calendar entry.
private struct CalendarOption: Identifiable {
    let id: String
    let summary: String
}

/// Finds the top-most view controller to present the Google sign-in sheet from.
@MainActor
private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController {
        top = presented
    }
    return top
}
