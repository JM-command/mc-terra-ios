//
//  ClientDetailView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData

/// The three tabs of a client's detail screen.
private enum ClientTab: String, CaseIterable, Identifiable {
    case infos
    case seances
    case actions

    var id: String { rawValue }
}

/// A client's detail sheet with three segmented tabs: Infos / Séances / Actions.
struct ClientDetailView: View {
    /// SwiftData object; edits are auto-saved.
    @Bindable var client: Client

    @State private var selectedTab: ClientTab = .infos

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
            tabContent
        }
        .navigationTitle(Text(verbatim: client.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tab switcher

    @ViewBuilder
    private var tabPicker: some View {
        Picker("Onglet", selection: $selectedTab) {
            Text("Infos").tag(ClientTab.infos)
            Text("Séances").tag(ClientTab.seances)
            Text("Actions").tag(ClientTab.actions)
        }
        .pickerStyle(.segmented)
        .padding()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .infos:
            ClientInfosTab(client: client)
        case .seances:
            ClientSeancesTab(client: client)
        case .actions:
            ClientActionsTab(client: client)
        }
    }
}

// MARK: - Infos tab

/// Editable client fields; SwiftData autosaves the bound object.
private struct ClientInfosTab: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            ClientSummarySection(client: client)
            Section("Client") {
                TextField("Nom", text: $client.name)
                TextField("Téléphone", text: $client.phone)
                    .keyboardType(.phonePad)
                Picker("Langue", selection: $client.language) {
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "Português").tag("pt")
                }
            }
            Section("Coordonnées") {
                TextField("E-mail", text: $client.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let url = emailURL {
                    Link(destination: url) {
                        Label("Écrire un e-mail", systemImage: "envelope.fill")
                    }
                }
                AddressAutocompleteField(address: $client.address)
                if let url = mapsURL {
                    Link(destination: url) {
                        Label("Voir sur Plans", systemImage: "map.fill")
                    }
                }
            }
            Section("Notes / résumé") {
                TextField("Notes", text: $client.notes, axis: .vertical)
                    .lineLimit(4...12)
            }
            Section {
                NavigationLink {
                    ClientNotesView(client: client)
                } label: {
                    HStack {
                        Label("Notes", systemImage: "note.text")
                        Spacer()
                        Text(verbatim: "\(client.noteEntries.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// mailto: vers l'e-mail du client (nil si vide).
    private var emailURL: URL? {
        let trimmed = client.email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }

    /// Lien Plans (Apple Maps) avec l'adresse encodée en requête (nil si vide).
    private var mapsURL: URL? {
        let trimmed = client.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }
}

// MARK: - Infos summary

/// At-a-glance recap of a client: total paid, session counts, next and last sessions.
/// All figures are derived from `client.seances` in Swift, no stored aggregates.
private struct ClientSummarySection: View {
    let client: Client

    /// Sum of priceCHF over finished and paid sessions (priceCHF > 0).
    private var totalSpentCHF: Double {
        client.seances
            .filter { $0.isCompleted && $0.priceCHF > 0 }
            .reduce(0) { $0 + $1.priceCHF }
    }

    private var totalSpentText: String {
        "\(totalSpentCHF.formatted(.number)) CHF"
    }

    private var totalCount: Int {
        client.seances.count
    }

    private var completedCount: Int {
        client.seances.filter(\.isCompleted).count
    }

    /// Soonest upcoming session (date in the future or now), or nil.
    private var nextSeance: Seance? {
        let now = Date.now
        return client.seances
            .filter { $0.date >= now }
            .min { $0.date < $1.date }
    }

    /// Most recent finished session in the past, or nil.
    private var lastCompletedSeance: Seance? {
        let now = Date.now
        return client.seances
            .filter { $0.isCompleted && $0.date <= now }
            .max { $0.date < $1.date }
    }

    var body: some View {
        Section("Résumé") {
            LabeledContent("Total dépensé") {
                Text(verbatim: totalSpentText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            LabeledContent("Séances") {
                Text(verbatim: "\(totalCount) (\(completedCount) terminées)")
            }
            LabeledContent("Prochaine séance") {
                if let next = nextSeance {
                    Text(next.date, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("Aucune")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Dernière séance") {
                if let last = lastCompletedSeance {
                    Text(last.date, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("Aucune")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Séances tab

/// Lists the client's sessions (most recent first) and opens a creation sheet.
private struct ClientSeancesTab: View {
    @Environment(\.modelContext) private var context
    /// Connexion Google partagée, pour supprimer aussi l'event lié au swipe-delete.
    @EnvironmentObject private var google: GoogleCalendarService
    /// Calendrier choisi dans les Réglages, "" quand aucun/déconnecté.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""
    @Bindable var client: Client

    /// Drives the running-session Live Activity + in-app timer.
    @StateObject private var liveSession = LiveSessionManager()

    @State private var showNewSeance = false
    /// The just-finished session whose summary/payment sheet is open.
    @State private var summarySeance: Seance?

    /// Sessions sorted most recent first.
    private var sortedSeances: [Seance] {
        client.seances.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            seanceList
            newSeanceButton
        }
        .sheet(isPresented: $showNewSeance) {
            NewSeanceView(client: client)
        }
        .sheet(item: $summarySeance) { seance in
            SeanceSummaryEditorView(seance: seance, language: client.language)
        }
    }

    @ViewBuilder
    private var seanceList: some View {
        if sortedSeances.isEmpty {
            ContentUnavailableView {
                Label("Aucune séance", systemImage: "calendar.badge.clock")
            } description: {
                Text("Ajoute la première séance de ce client.")
            }
        } else {
            List {
                ForEach(sortedSeances) { seance in
                    VStack(spacing: 8) {
                        NavigationLink {
                            SeanceDetailView(seance: seance)
                        } label: {
                            SeanceRow(seance: seance)
                        }

                        seanceControls(for: seance)
                    }
                    // Swipe-to-delete only on planned sessions; finished ones are locked.
                    .deleteDisabled(seance.isCompleted)
                }
                .onDelete(perform: deleteSeances)
            }
        }
    }

    /// Start / Terminer controls for a startable, not-yet-finished session.
    @ViewBuilder
    private func seanceControls(for seance: Seance) -> some View {
        // Only startable sessions: planned, whose date is today or in the past.
        if !seance.isCompleted, seance.date <= Date.now {
            if liveSession.isRunning(seance) {
                HStack(spacing: 12) {
                    if let start = liveSession.activeStart {
                        Label {
                            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        finishRunningSession(seance)
                    } label: {
                        Label("Terminer", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else if !liveSession.isRunning {
                // No session running at all: offer to start this one.
                Button {
                    liveSession.start(for: seance)
                } label: {
                    Label("Démarrer la séance", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Ends the Live Activity, locks the session, then opens the summary/payment flow.
    private func finishRunningSession(_ seance: Seance) {
        Task {
            await liveSession.end()
            // Lock the session and drop its reminder, mirroring NewSeanceView's flow.
            seance.status = SeanceStatus.completed
            NotificationService.cancel(for: seance)
            summarySeance = seance
        }
    }

    @ViewBuilder
    private var newSeanceButton: some View {
        Button {
            showNewSeance = true
        } label: {
            Label("Nouvelle séance", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    private func deleteSeances(at offsets: IndexSet) {
        for index in offsets {
            let seance = sortedSeances[index]
            // Guard: finished sessions stay locked even if a swipe slips through.
            guard !seance.isCompleted else { continue }
            // Supprime l'event Google lié (best-effort) : on capture eventId +
            // calendarId AVANT le context.delete, comme SeanceDetailView.deleteSeance().
            let eventId = seance.googleEventId
            let calendarId = googleCalendarId
            if google.isSignedIn, !calendarId.isEmpty, !eventId.isEmpty {
                Task { await google.deleteEvent(calendarId: calendarId, eventId: eventId) }
            }
            // Drop any pending 5-min reminder before removing the session.
            NotificationService.cancel(for: seance)
            context.delete(seance)
        }
        // Resync la liste push après suppression (sinon timer pour séance morte).
        PushToStartService.shared.sync(using: context)
    }
}

/// A single row summarizing a session.
private struct SeanceRow: View {
    let seance: Seance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(seance.date, format: .dateTime.day().month().year().hour().minute())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: priceText)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            HStack(spacing: 6) {
                Text(verbatim: seance.serviceName)
                    .font(.caption)
                Text(verbatim: "·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(seance.durationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let method = PaymentMethod(stored: seance.paymentMethod) {
                    Label(method.displayName, systemImage: method.icon)
                        .font(.caption2)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tint)
                }
                SeanceStatusBadge(status: seance.status)
            }
            if !seance.note.isEmpty {
                Text(verbatim: seance.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var priceText: String {
        "\(seance.priceCHF.formatted(.number)) CHF"
    }
}

// MARK: - Actions tab

/// Quick contact actions: WhatsApp, call, and ready-to-send message templates.
private struct ClientActionsTab: View {
    @Bindable var client: Client

    /// The template whose form sheet is currently presented (templates that need a field).
    @State private var formTemplate: MessageTemplate?

    /// Phone digits only (no spaces, no leading "+"), for wa.me links.
    private var cleanedPhone: String {
        client.phone.filter(\.isNumber)
    }

    private var hasPhone: Bool {
        !cleanedPhone.isEmpty
    }

    /// First name, used to personalize the WhatsApp greeting.
    private var firstName: String {
        client.name
            .split(separator: " ")
            .first
            .map(String.init) ?? client.name
    }

    var body: some View {
        Form {
            Section {
                whatsAppButton
                callButton
            }
            messagesSection
        }
        .sheet(item: $formTemplate) { template in
            MessageTemplateFormSheet(client: client, template: template)
        }
    }

    // MARK: - Ready-to-send messages

    @ViewBuilder
    private var messagesSection: some View {
        Section("Messages prêts") {
            ForEach(MessageTemplate.all) { template in
                MessageTemplateRow(
                    template: template,
                    isEnabled: hasPhone,
                    action: { handle(template) }
                )
            }
        }
    }

    /// Templates with a form open the sheet; the others open WhatsApp directly.
    private func handle(_ template: MessageTemplate) {
        guard hasPhone else { return }
        if template.field != nil {
            formTemplate = template
        } else {
            let body = template.body(for: client)
            if let url = MessageTemplate.whatsAppURL(phone: client.phone, body: body) {
                openURL(url)
            }
        }
    }

    @Environment(\.openURL) private var openURL

    @ViewBuilder
    private var whatsAppButton: some View {
        if let url = whatsAppURL {
            Link(destination: url) {
                Label("Message WhatsApp", systemImage: "message.fill")
            }
        } else {
            Label("Message WhatsApp", systemImage: "message.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var callButton: some View {
        if let url = callURL {
            Link(destination: url) {
                Label("Appeler", systemImage: "phone.fill")
            }
        } else {
            Label("Appeler", systemImage: "phone.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - URLs

    /// https://wa.me/<digits>?text=<encoded greeting>
    private var whatsAppURL: URL? {
        guard hasPhone else { return nil }
        let greeting = String(localized: "Bonjour \(firstName)")
        let encoded = greeting.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? ""
        return URL(string: "https://wa.me/\(cleanedPhone)?text=\(encoded)")
    }

    /// tel:<original phone>
    private var callURL: URL? {
        guard hasPhone else { return nil }
        return URL(string: "tel:\(cleanedPhone)")
    }
}

#Preview {
    NavigationStack {
        ClientDetailView(client: Client(name: "Marta Coelho", phone: "+41 79 123 45 67"))
    }
    .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
