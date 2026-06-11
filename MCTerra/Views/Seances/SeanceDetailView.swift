//
//  SeanceDetailView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit

/// Dedicated detail screen for a single session.
///
/// Opened directly from the agenda (or from a client's "Séances" tab) so the
/// session's actions are one tap away instead of buried behind the client sheet.
/// It reuses the exact flows of `ClientDetailView`'s session tab: start/finish a
/// live session (`LiveSessionManager` + in-app timer), edit/delete a planned one
/// (`NewSeanceView`), and edit a finished one's summary (`SeanceSummaryEditorView`).
struct SeanceDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Shared Google Calendar connection, used to remove the linked event on delete.
    @EnvironmentObject private var google: GoogleCalendarService

    /// The calendar synced with Google, "" when none. Used to target the delete.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""

    /// SwiftData object; edits are auto-saved.
    @Bindable var seance: Seance

    /// When opened via the Live Activity Stop control (`?finish=1`), immediately
    /// runs the finish flow (end activity → summary + payment).
    var autoFinish: Bool = false

    /// Drives the running-session Live Activity + in-app timer.
    @StateObject private var liveSession = LiveSessionManager()

    /// Drives the edit sheet (`NewSeanceView`) for a planned session.
    @State private var showEdit = false
    /// Drives the summary/payment editor sheet (`SeanceSummaryEditorView`).
    @State private var showSummary = false
    /// Confirms a destructive delete of a planned session.
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            SeanceHeaderSection(seance: seance)
            actionsSection
            contactSection
        }
        .navigationTitle(Text(verbatim: clientName))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            NewSeanceView(client: seance.client, seance: seance)
        }
        .sheet(isPresented: $showSummary) {
            SeanceSummaryEditorView(seance: seance, language: seance.client?.language ?? "fr")
        }
        .alert("Supprimer la séance ?", isPresented: $showDeleteConfirm) {
            Button("Supprimer", role: .destructive) { deleteSeance() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est définitive.")
        }
        // Mirror the system Live Activity for this session: reflects a session
        // started or stopped from the lock screen, and updates the timer live.
        .task(id: seance.uuid) {
            await liveSession.observe(seance)
        }
        // Opened from the lock-screen Stop control: run the finish flow right away.
        .task {
            guard autoFinish, !seance.isCompleted else { return }
            liveSession.sync(with: seance)
            finishRunningSession()
        }
        // Re-sync when returning from the lock screen (where Stop may have run).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { liveSession.sync(with: seance) }
        }
    }

    // MARK: - Derived state

    private var clientName: String {
        seance.client?.name ?? String(localized: "Sans client")
    }

    /// A planned session whose date/time has already passed: it can be started.
    private var isStartable: Bool {
        !seance.isCompleted && seance.date <= Date.now
    }

    /// A planned session still in the future: it can be edited or deleted.
    private var isUpcoming: Bool {
        !seance.isCompleted && seance.date > Date.now
    }

    // MARK: - Actions section

    @ViewBuilder
    private var actionsSection: some View {
        if seance.isCompleted {
            completedActions
        } else if isStartable {
            startableActions
        } else {
            upcomingActions
        }
    }

    /// Finished session: read-only summary + payment, with a button to edit the summary.
    @ViewBuilder
    private var completedActions: some View {
        SeanceSummarySection(seance: seance)
        Section {
            Button {
                showSummary = true
            } label: {
                Label("Modifier le résumé", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// Past planned session: start the live session directly (screen + Live
    /// Activity), then finish it. Running → timer + Terminer.
    @ViewBuilder
    private var startableActions: some View {
        Section {
            if liveSession.isRunning(seance), liveSession.isLive {
                runningTimerRow
                finishButton
            } else {
                startButton
                // Pas de timer en cours : on autorise le marquage "Client absent"
                // et la suppression (bug : "Supprimer" disparaissait dès l'heure passée).
                if !liveSession.isRunning(seance) {
                    noShowButton
                    deleteButton
                }
            }
        }
    }

    /// Marque la séance comme "Client absent" (no-show) : reste en base mais
    /// n'est ni facturée ni poussée au push-to-start.
    @ViewBuilder
    private var noShowButton: some View {
        Button {
            markNoShow()
        } label: {
            Label("Client absent", systemImage: "person.slash")
                .frame(maxWidth: .infinity)
        }
        // Même style plein-largeur que les autres boutons de la vue (start/finish) :
        // bouton prominent opaque, orange, sans séparateur gris qui coupe au milieu.
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Supprime la séance planifiée (même style/label que dans `upcomingActions`).
    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Supprimer", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        // Aligné sur le "Supprimer" prominent rouge de `upcomingActions`.
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var runningTimerRow: some View {
        if let start = liveSession.activeStart {
            Label {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .font(.headline)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
        }
    }

    /// Starts the session running. If it was already prepared on the lock screen,
    /// flips it live (`markRunning`); otherwise starts a running activity directly.
    @ViewBuilder
    private var startButton: some View {
        Button {
            if liveSession.isRunning(seance) {
                liveSession.markRunning()
            } else {
                liveSession.start(for: seance)
            }
        } label: {
            Label("Démarrer la séance", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        // Empilé proprement avec "Client absent" / "Supprimer" en dessous,
        // sans séparateur gris entre les boutons.
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var finishButton: some View {
        Button(role: .destructive) {
            finishRunningSession()
        } label: {
            Label("Terminer la séance", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// Future planned session: edit or delete.
    @ViewBuilder
    private var upcomingActions: some View {
        Section {
            Button {
                showEdit = true
            } label: {
                Label("Modifier", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Supprimer", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Contact section

    /// WhatsApp message to the client, enabled only when a phone is set.
    @ViewBuilder
    private var contactSection: some View {
        Section {
            if let url = whatsAppURL {
                Link(destination: url) {
                    Label("Message WhatsApp", systemImage: "message.fill")
                }
            } else {
                Label("Message WhatsApp", systemImage: "message.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logic

    /// Phone digits only (no spaces, no leading "+"), for wa.me links.
    private var cleanedPhone: String {
        seance.client?.phone.filter(\.isNumber) ?? ""
    }

    /// First name, used to personalize the WhatsApp greeting.
    private var firstName: String {
        let name = seance.client?.name ?? ""
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// https://wa.me/<digits>?text=<encoded greeting>
    private var whatsAppURL: URL? {
        guard !cleanedPhone.isEmpty else { return nil }
        let greeting = String(localized: "Bonjour \(firstName)")
        let encoded = greeting.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? ""
        return URL(string: "https://wa.me/\(cleanedPhone)?text=\(encoded)")
    }

    /// Ends the Live Activity, locks the session, then opens the summary/payment flow.
    private func finishRunningSession() {
        Task {
            await liveSession.end()
            // Lock the session and drop its reminder, mirroring ClientDetailView's flow.
            seance.status = SeanceStatus.completed
            // Flush explicite sur disque : l'auto-save SwiftData ne garantit pas
            // d'écrire avant que l'app soit tuée (swipe), le statut "terminee" se
            // perdait et la séance redevenait "planifiée" au redémarrage.
            try? context.save()
            NotificationService.cancel(for: seance)
            // Resync : le statut passe à "terminee", le serveur ne doit plus pousser
            // cette séance au push-to-start.
            PushToStartService.shared.sync(using: context)
            showSummary = true
        }
    }

    /// Marque la séance comme "Client absent" (no-show) : on garde la séance en
    /// base mais on annule ses notifs locales, on resync le serveur pour la retirer
    /// du push-to-start, on rafraîchit les widgets puis on quitte l'écran.
    private func markNoShow() {
        seance.noShow = true
        NotificationService.cancel(for: seance)
        PushToStartService.shared.sync(using: context)
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }

    /// Drops the pending reminder, removes the session, and pops the screen.
    /// If the session is linked to a Google event, removes it there too
    /// (best-effort: offline / signed-out / 403 just no-op, no crash).
    private func deleteSeance() {
        guard !seance.isCompleted else { return }

        // Capture the link before the local object is deleted.
        let eventId = seance.googleEventId
        let calendarId = googleCalendarId
        if google.isSignedIn, !calendarId.isEmpty, !eventId.isEmpty {
            Task { await google.deleteEvent(calendarId: calendarId, eventId: eventId) }
        }

        NotificationService.cancel(for: seance)
        context.delete(seance)
        // Reflect the deletion in the home-screen widgets.
        WidgetCenter.shared.reloadAllTimelines()
        // Resync : sans ça le serveur garde la séance et continue de la pousser
        // au push-to-start tant qu'il n'est pas resync.
        PushToStartService.shared.sync(using: context)
        dismiss()
    }
}

// MARK: - Header section

/// Top section: client, date/time, service, duration, price, location, status, note.
private struct SeanceHeaderSection: View {
    let seance: Seance

    var body: some View {
        Section {
            LabeledContent("Client") {
                Text(verbatim: seance.client?.name ?? String(localized: "Sans client"))
            }
            LabeledContent("Date") {
                Text(seance.date, format: .dateTime.weekday().day().month().year().hour().minute())
            }
            LabeledContent("Forfait") {
                Text(verbatim: seance.serviceName)
            }
            LabeledContent("Durée") {
                Text(verbatim: formattedDuration)
            }
            LabeledContent("Prix") {
                Text(verbatim: priceText)
                    .foregroundStyle(.tint)
            }
            // Location inlined (not a separate @ViewBuilder property): a computed
            // property returning an optional view inserted a phantom empty row here.
            if let place = SessionLocation(stored: seance.location) {
                HStack {
                    Text("Lieu")
                    Spacer()
                    Label(place.displayName, systemImage: place.icon)
                        .foregroundStyle(.tint)
                }
            }
            HStack {
                Text("Statut")
                Spacer()
                SeanceStatusBadge(status: seance.status)
            }
            // Planned note shown inline (a finished session has its own Résumé section).
            if !seance.isCompleted, !seance.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: seance.note)
                }
            }
        }
    }

    /// Formatted duration (e.g. "1 h 07").
    private var formattedDuration: String {
        let hours = seance.durationMinutes / 60
        let mins = seance.durationMinutes % 60
        if hours > 0 {
            return "\(hours) h \(String(format: "%02d", mins))"
        }
        return "\(mins) min"
    }

    private var priceText: String {
        "\(seance.priceCHF.formatted(.number)) CHF"
    }
}

// MARK: - Summary section (finished sessions)

/// Read-only summary + recorded payment method for a finished session.
private struct SeanceSummarySection: View {
    let seance: Seance

    var body: some View {
        Section("Résumé") {
            if seance.note.isEmpty {
                Text("Aucun résumé pour l'instant.")
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: seance.note)
            }
            if let method = PaymentMethod(stored: seance.paymentMethod) {
                LabeledContent("Moyen de paiement") {
                    Label(method.displayName, systemImage: method.icon)
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

#Preview("Planifiée") {
    NavigationStack {
        SeanceDetailView(
            seance: Seance(
                serviceName: "Thérapie Émotionnelle",
                durationMinutes: 67,
                priceCHF: 80,
                location: "cabinet",
                client: Client(name: "Marta Coelho", phone: "+41 79 123 45 67")
            )
        )
    }
    .modelContainer(for: [Client.self, Seance.self], inMemory: true)
    .environmentObject(GoogleCalendarService())
}
