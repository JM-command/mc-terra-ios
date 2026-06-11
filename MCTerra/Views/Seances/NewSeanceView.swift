//
//  NewSeanceView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit

/// Sheet to create a new session or edit an existing one for a given client.
///
/// - Creation: `seance` is `nil`; picking a forfait pre-fills duration and price.
/// - Edition: pass an existing `seance`. While it is "planifiee" every field is
///   editable; once "terminee" the core fields (date/service/duration/price) are
///   locked and only the summary (`note`) stays editable.
struct NewSeanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Shared Google Calendar connection, used to push sessions to Google (Phase B).
    @EnvironmentObject private var google: GoogleCalendarService

    /// The calendar the user chose to sync with, "" when none. Drives whether we
    /// push this session to Google after saving.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""

    /// The client this session is attached to. `nil` for a standalone "Nouvelle
    /// séance" created from the agenda, where the client is picked or typed below.
    let client: Client?

    /// Existing session being edited, or `nil` when creating a new one.
    let seance: Seance?

    /// All clients, to populate the picker when creating a standalone session.
    @Query(sort: \Client.name) private var clients: [Client]

    /// Marta's editable forfaits, ordered as in Settings. Drives the forfait picker.
    @Query(sort: [SortDescriptor(\Forfait.sortOrder), SortDescriptor(\Forfait.name)])
    private var forfaits: [Forfait]

    /// Picked existing client (its id), or `nil` to type a new client's name.
    @State private var selectedClientID: PersistentIdentifier?
    /// Free-text name when creating a brand-new client inline.
    @State private var newClientName: String = ""

    /// Currently-picked forfait identity. A `Forfait`'s uuid selects that forfait;
    /// `nil` means the free "Personnalisé" option (duration/price typed by hand).
    @State private var selectedForfaitUUID: UUID?
    /// The session's service label. For a forfait it mirrors the forfait name; for
    /// "Personnalisé" it stays the localized "Personnalisé" (or a kept custom label
    /// when editing a session whose service is not a known forfait).
    @State private var serviceName: String
    @State private var date: Date
    @State private var durationMinutes: Int
    @State private var durationHours: Int
    @State private var durationMins: Int
    @State private var priceCHF: Double
    @State private var note: String
    /// Where the session takes place. Defaults to cabinet for new sessions.
    @State private var location: SessionLocation
    /// Local mirror of `seance?.status`; lets the UI react when "Terminer" is tapped.
    @State private var status: String

    /// Drives the summary editor sheet opened by "Terminer la séance".
    @State private var showSummaryEditor = false

    /// True while the initial forfait selection is being resolved on appear. Guards
    /// against the selection's `onChange` clobbering an edited session's stored
    /// duration/price with the forfait defaults; cleared once resolution is done.
    @State private var isResolvingInitial = false

    init(client: Client? = nil, seance: Seance? = nil) {
        self.client = client
        self.seance = seance
        // Standalone creation: default the picker to the given client when present.
        _selectedClientID = State(initialValue: client?.persistentModelID)

        // Seed the form from the existing session, or from sensible defaults.
        // The forfait selection is resolved in `resolveInitialForfait()` once the
        // `@Query` forfaits are available (not yet in `init`).
        if let seance {
            _serviceName = State(initialValue: seance.serviceName)
            _date = State(initialValue: seance.date)
            _durationMinutes = State(initialValue: seance.durationMinutes)
            let hours = seance.durationMinutes / 60
            let mins = seance.durationMinutes % 60
            _durationHours = State(initialValue: hours)
            _durationMins = State(initialValue: mins)
            _priceCHF = State(initialValue: seance.priceCHF)
            _note = State(initialValue: seance.note)
            _location = State(initialValue: SessionLocation(stored: seance.location) ?? .cabinet)
            _status = State(initialValue: seance.status)
        } else {
            _serviceName = State(initialValue: String(localized: "Personnalisé"))
            _date = State(initialValue: .now)
            _durationMinutes = State(initialValue: 60)
            _durationHours = State(initialValue: 1)
            _durationMins = State(initialValue: 0)
            _priceCHF = State(initialValue: 0)
            _note = State(initialValue: "")
            _location = State(initialValue: .cabinet)
            _status = State(initialValue: SeanceStatus.planned)
        }
        // Custom by default; resolved to a real forfait in `resolveInitialForfait()`.
        _selectedForfaitUUID = State(initialValue: nil)
    }

    // MARK: - Derived state

    /// True when editing an existing, finished session: core fields are locked.
    private var isLocked: Bool { status == SeanceStatus.completed }

    private var isEditing: Bool { seance != nil }

    /// "Terminer" only appears once the session's date/time has passed.
    private var hasStarted: Bool { date <= Date.now }

    private var navigationTitle: LocalizedStringKey {
        isEditing ? "Modifier la séance" : "Nouvelle séance"
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                clientSection
                serviceSection
                detailsSection
                noteSection
                if isEditing, !isLocked, hasStarted {
                    completeSection
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
            // Re-fill name, duration and price when the forfait changes (locked sessions
            // stay untouched, and the initial edit-resolution must not clobber stored values).
            .onChange(of: selectedForfaitUUID) { _, newValue in
                guard !isLocked, !isResolvingInitial else { return }
                applyForfait(uuid: newValue)
            }
            // Resolve which forfait is selected once the query has loaded.
            .onAppear { resolveInitialForfait() }
            // Keep durationMinutes in sync with hours and minutes pickers.
            .onChange(of: durationHours) { _, _ in
                syncDurationMinutes()
            }
            .onChange(of: durationMins) { _, _ in
                syncDurationMinutes()
            }
            .sheet(isPresented: $showSummaryEditor) {
                if let seance {
                    SeanceSummaryEditorView(seance: seance, language: seance.client?.language ?? "fr")
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        if isEditing {
            Section {
                HStack {
                    Text("Statut")
                    Spacer()
                    SeanceStatusBadge(status: status)
                }
            }
        }
    }

    /// Client chooser, shown only when creating a standalone session (not when the
    /// view is opened from a specific client's fiche, nor when editing). Pushes a
    /// searchable picker so it scales to many clients.
    @ViewBuilder
    private var clientSection: some View {
        if client == nil, !isEditing {
            Section("Client") {
                NavigationLink {
                    ClientChooser(
                        clients: clients,
                        selectedClientID: $selectedClientID,
                        newClientName: $newClientName
                    )
                } label: {
                    HStack {
                        Text("Client")
                        Spacer()
                        Text(verbatim: chosenClientLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Label of the currently-chosen client (existing name, typed new name, or a
    /// "à choisir" placeholder).
    private var chosenClientLabel: String {
        if let id = selectedClientID, let c = clients.first(where: { $0.persistentModelID == id }) {
            return c.name
        }
        let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "À choisir") : name
    }

    @ViewBuilder
    private var serviceSection: some View {
        Section("Forfait") {
            Picker("Forfait", selection: $selectedForfaitUUID) {
                ForEach(forfaits) { forfait in
                    Text(verbatim: forfait.name).tag(Optional(forfait.uuid))
                }
                // Free option: the user types duration and price by hand.
                Text("Personnalisé").tag(UUID?.none)
            }
            .disabled(isLocked)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section("Détails") {
            DatePicker("Date", selection: $date)
                .disabled(isLocked)

            Picker("Lieu", selection: $location) {
                ForEach(SessionLocation.allCases) { place in
                    Label(place.displayName, systemImage: place.icon).tag(place)
                }
            }
            .disabled(isLocked)

            durationPicker

            HStack {
                Text("Prix")
                Spacer()
                TextField("Prix", value: $priceCHF, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 100)
                    .disabled(isLocked)
                Text(verbatim: "CHF")
                    .foregroundStyle(.secondary)
            }

            // Show the recorded payment method on a finished, paid session.
            if isLocked, let method = PaymentMethod(stored: seance?.paymentMethod ?? "") {
                HStack {
                    Text("Moyen de paiement")
                    Spacer()
                    Label(method.displayName, systemImage: method.icon)
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    /// Compact duration row: a pill showing the formatted value that, on tap,
    /// reveals two inline wheels (hours / minutes). Locked sessions show text only.
    @ViewBuilder
    private var durationPicker: some View {
        if isLocked {
            // Read-only display once the session is finished.
            HStack {
                Text("Durée")
                Spacer()
                Text(formatDurationReadOnly(durationMinutes))
                    .foregroundStyle(.secondary)
            }
        } else {
            DurationCompactPicker(
                hours: $durationHours,
                minutes: $durationMins,
                formattedValue: formatDurationReadOnly(durationMinutes)
            )
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        // The summary stays editable even when the session is locked.
        Section(isLocked ? "Résumé" : "Note") {
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var completeSection: some View {
        Section {
            Button {
                completeSeance()
            } label: {
                Label("Terminer la séance", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Logic

    /// Syncs durationMinutes = durationHours * 60 + durationMins whenever picker changes.
    private func syncDurationMinutes() {
        durationMinutes = durationHours * 60 + durationMins
    }

    /// Looks up the selected forfait, or `nil` for "Personnalisé".
    private var selectedForfait: Forfait? {
        guard let id = selectedForfaitUUID else { return nil }
        return forfaits.first { $0.uuid == id }
    }

    /// Applies the picked forfait's name, duration and price. "Personnalisé"
    /// (nil uuid) only sets the localized label and leaves duration/price as typed.
    private func applyForfait(uuid: UUID?) {
        guard let id = uuid, let forfait = forfaits.first(where: { $0.uuid == id }) else {
            serviceName = String(localized: "Personnalisé")
            return
        }
        serviceName = forfait.name
        durationMinutes = forfait.durationMinutes
        durationHours = durationMinutes / 60
        durationMins = durationMinutes % 60
        priceCHF = forfait.priceCHF
    }

    /// Resolves the initial forfait selection once the `@Query` has loaded.
    ///
    /// - Editing: select the forfait whose name matches the stored `serviceName`
    ///   (case-insensitive); none matches means the session keeps a free label, so
    ///   stay on "Personnalisé" and preserve the stored values.
    /// - Creating: default to the first forfait when one exists (pre-fills the form),
    ///   otherwise stay on "Personnalisé".
    private func resolveInitialForfait() {
        if isEditing {
            if let match = forfaits.first(where: {
                $0.name.caseInsensitiveCompare(serviceName) == .orderedSame
            }) {
                // Set the picker selection without re-filling: the stored duration and
                // price must survive. The guard is lifted on the next runloop, after
                // the selection's onChange has had its chance to fire.
                isResolvingInitial = true
                selectedForfaitUUID = match.uuid
                DispatchQueue.main.async { isResolvingInitial = false }
            }
            return
        }
        // New session: default to the first forfait. The selection's onChange then
        // pre-fills name, duration and price.
        if selectedForfaitUUID == nil, let first = forfaits.first {
            selectedForfaitUUID = first.uuid
        }
    }

    /// Format duration in read-only mode (e.g. "1 h 07").
    private func formatDurationReadOnly(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 {
            return "\(hours) h \(String(format: "%02d", mins))"
        } else {
            return "\(mins) min"
        }
    }

    /// The service label saved on the session: the picked forfait's name, or the
    /// localized "Personnalisé" label (or a kept free label when editing).
    private var resolvedServiceName: String {
        if let forfait = selectedForfait { return forfait.name }
        return serviceName
    }

    /// Resolves the client for a standalone creation: the fixed one if provided,
    /// otherwise the picked existing client, otherwise an existing client matching
    /// the typed name (case-insensitive) to avoid duplicates, otherwise a new one
    /// (or `nil` for a session with no client yet).
    private func resolveClient() -> Client? {
        if let client { return client }
        if let id = selectedClientID {
            return clients.first { $0.persistentModelID == id }
        }
        let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let existing = clients.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        let created = Client(name: name)
        context.insert(created)
        return created
    }

    private func save() {
        // The session that was created or edited, so we can push it to Google.
        let saved: Seance

        if let seance {
            // Edition: when locked, only the summary may change.
            if isLocked {
                seance.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                seance.date = date
                seance.serviceName = resolvedServiceName
                seance.durationMinutes = durationMinutes
                seance.priceCHF = priceCHF
                seance.location = location.rawValue
                seance.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                // Re-sync the 5-min reminder to the (possibly new) date.
                NotificationService.schedule(for: seance)
            }
            saved = seance
        } else {
            // Creation.
            let new = Seance(
                date: date,
                serviceName: resolvedServiceName,
                durationMinutes: durationMinutes,
                priceCHF: priceCHF,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                location: location.rawValue,
                client: resolveClient()
            )
            context.insert(new)
            // Schedule the "get ready" reminder for future sessions.
            NotificationService.schedule(for: new)
            saved = new
        }
        // Reflect the create/edit in the home-screen widgets.
        WidgetCenter.shared.reloadAllTimelines()
        // Resync la liste push (couvre création ET déplacement, sinon le timer
        // lock-screen reste sur l'ancienne heure ou s'allume pour rien).
        PushToStartService.shared.sync(using: context)

        // Best-effort push to Google Calendar; never blocks dismissal nor crashes.
        pushToGoogle(saved)
        dismiss()
    }

    /// Mirrors the saved session to Google Calendar when connected and a calendar
    /// is selected. Creates a new event when none exists yet, otherwise updates the
    /// linked one (which also covers sessions that were imported from Google, since
    /// those already carry a `googleEventId` — so we never recreate and loop).
    /// Runs detached and silent: offline / signed-out / 403 simply no-op.
    private func pushToGoogle(_ seance: Seance) {
        guard google.isSignedIn, !googleCalendarId.isEmpty else { return }
        let calendarId = googleCalendarId
        Task { @MainActor in
            if seance.googleEventId.isEmpty {
                if let newId = await google.createEvent(calendarId: calendarId, for: seance) {
                    seance.googleEventId = newId
                }
            } else {
                await google.updateEvent(
                    calendarId: calendarId,
                    eventId: seance.googleEventId,
                    for: seance
                )
            }
        }
    }

    /// Persists current edits, flips the session to "terminee", then opens the summary editor.
    private func completeSeance() {
        guard let seance else { return }
        // Persist any pending core edits before locking.
        seance.date = date
        seance.serviceName = resolvedServiceName
        seance.durationMinutes = durationMinutes
        seance.priceCHF = priceCHF
        seance.location = location.rawValue
        seance.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        seance.status = SeanceStatus.completed
        status = SeanceStatus.completed
        // A finished session no longer needs its "get ready" reminder.
        NotificationService.cancel(for: seance)
        showSummaryEditor = true
    }
}

// MARK: - Duration compact picker

/// A compact, expandable duration control matching the look of a `.compact` DatePicker.
///
/// Collapsed: a "Durée" label with a tappable pill (e.g. "1 h 07") on the right.
/// Expanded: the same row plus two side-by-side wheels (hours 0...23, minutes 0...59).
/// The bound `hours` / `minutes` drive `durationMinutes` in the parent via its onChange.
private struct DurationCompactPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    /// Pre-formatted total duration shown inside the pill (e.g. "1 h 07").
    let formattedValue: String

    /// Whether the wheels are currently revealed.
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Tappable header row, styled like the Date row above it.
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Durée")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formattedValue)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(pillBackground, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline wheels, revealed only while expanded.
            if isExpanded {
                HStack(spacing: 0) {
                    // Hours wheel
                    Picker("Heures", selection: $hours) {
                        ForEach(0...23, id: \.self) { hour in
                            Text("\(hour) h").tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    // Minutes wheel
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0...59, id: \.self) { minute in
                            Text("\(String(format: "%02d", minute)) min").tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 140)
            }
        }
    }

    /// Tinted while expanded, neutral otherwise — mirrors a compact DatePicker pill.
    private var pillBackground: some ShapeStyle {
        isExpanded ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(Color(.secondarySystemFill))
    }
}

// MARK: - Status badge

/// Small pill showing whether a session is planned or finished.
struct SeanceStatusBadge: View {
    let status: String

    private var isCompleted: Bool { status == SeanceStatus.completed }

    var body: some View {
        Text(isCompleted ? "Terminée" : "Planifiée")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeBackground, in: Capsule())
            .foregroundStyle(badgeForeground)
    }

    private var badgeBackground: some ShapeStyle {
        isCompleted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.secondary.opacity(0.15))
    }

    private var badgeForeground: some ShapeStyle {
        isCompleted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }
}

// MARK: - Client chooser (searchable)

/// Searchable client picker pushed from the "Nouvelle séance" form, so choosing a
/// client scales past a long Picker. Tapping a client selects it; typing a name
/// that doesn't exist offers to create it.
private struct ClientChooser: View {
    let clients: [Client]
    @Binding var selectedClientID: PersistentIdentifier?
    @Binding var newClientName: String

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [Client] {
        guard !trimmedSearch.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    /// True when the search text isn't already an exact existing client name.
    private var canCreate: Bool {
        !trimmedSearch.isEmpty
            && !clients.contains { $0.name.caseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    var body: some View {
        List {
            if canCreate {
                Button {
                    newClientName = trimmedSearch
                    selectedClientID = nil
                    dismiss()
                } label: {
                    Label("Créer « \(trimmedSearch) »", systemImage: "person.badge.plus")
                }
            }
            ForEach(filtered) { c in
                Button {
                    selectedClientID = c.persistentModelID
                    newClientName = ""
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: c.name)
                        Spacer()
                        if selectedClientID == c.persistentModelID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $search, prompt: Text("Rechercher un client"))
        .navigationTitle("Choisir le client")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Création") {
    NewSeanceView(client: Client(name: "Marta"))
        .modelContainer(for: [Client.self, Seance.self, Forfait.self], inMemory: true)
        .environmentObject(GoogleCalendarService())
}
