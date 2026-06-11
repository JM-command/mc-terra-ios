//
//  SeanceSummaryEditorView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import WidgetKit

/// Editor for a finished session's summary (`Seance.note`).
///
/// Offers a multiline text field plus a mic button that dictates through
/// `SpeechRecognizer`. On stop, the transcribed text is appended to the field.
/// Stays usable later on: the summary remains editable even after the session
/// is marked "terminee".
struct SeanceSummaryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    /// Contexte SwiftData : sert à flusher explicitement le résumé/paiement sur
    /// disque (l'auto-save ne garantit pas l'écriture avant un kill de l'app).
    @Environment(\.modelContext) private var context

    /// The (finished) session whose summary is being edited.
    @Bindable var seance: Seance
    /// Client language code ("fr"/"pt") used to set the recognizer locale.
    let language: String

    @StateObject private var speech = SpeechRecognizer()

    /// Local draft so dictation can append cleanly before persisting.
    @State private var draft: String
    @State private var micAuthorized = false
    @State private var showPermissionAlert = false
    /// Length of `draft` when dictation started, so we replace only the dictated tail.
    @State private var dictationAnchor: Int = 0
    /// Selected payment method, or `nil` while unpaid (e.g. a free session).
    @State private var paymentMethod: PaymentMethod?
    /// Editable price confirmed at the moment the session is finished.
    @State private var priceCHF: Double

    init(seance: Seance, language: String) {
        self.seance = seance
        self.language = language
        _draft = State(initialValue: seance.note)
        _paymentMethod = State(initialValue: PaymentMethod(stored: seance.paymentMethod))
        _priceCHF = State(initialValue: seance.priceCHF)
    }

    var body: some View {
        NavigationStack {
            Form {
                paymentSection
                summaryField
                micSection
            }
            .navigationTitle("Résumé de la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        stopAndPersist()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        stopAndPersist()
                        dismiss()
                    }
                }
            }
            .onAppear {
                speech.setLanguage(language)
            }
            .onDisappear {
                speech.stop()
            }
            // Live append of the transcript while dictating.
            .onChange(of: speech.transcript) { _, newValue in
                applyTranscript(newValue)
            }
            .alert("Micro non autorisé", isPresented: $showPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Autorise le micro et la reconnaissance vocale dans les Réglages pour dicter le résumé.")
            }
        }
    }

    // MARK: - Sections

    /// Payment method (segmented Twint / Carte / Espèces) plus an editable price.
    @ViewBuilder
    private var paymentSection: some View {
        Section {
            Picker("Moyen de paiement", selection: $paymentMethod) {
                ForEach(PaymentMethod.allCases) { method in
                    Label(method.displayName, systemImage: method.icon)
                        .tag(Optional(method))
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Prix")
                Spacer()
                TextField("Prix", value: $priceCHF, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 100)
                Text(verbatim: "CHF")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Paiement")
        } footer: {
            Text("Une séance gratuite peut rester sans paiement.")
        }
    }

    @ViewBuilder
    private var summaryField: some View {
        Section("Résumé") {
            TextField("Résumé de la séance", text: $draft, axis: .vertical)
                .lineLimit(6...14)
        }
    }

    @ViewBuilder
    private var micSection: some View {
        Section {
            Button {
                toggleDictation()
            } label: {
                Label(
                    speech.isRecording ? "Arrêter la dictée" : "Dicter le résumé",
                    systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(speech.isRecording ? .red : Color.accentColor)

            if speech.isRecording {
                WaveformView(levels: speech.levels)
                    .frame(height: 28)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
        } footer: {
            Text("La dictée vient compléter le résumé. Tu peux toujours le corriger à la main.")
        }
    }

    // MARK: - Dictation

    private func toggleDictation() {
        if speech.isRecording {
            stopAndPersist()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        Task {
            let granted = await speech.requestAuthorization()
            guard granted else {
                showPermissionAlert = true
                return
            }
            micAuthorized = true
            speech.setLanguage(language)
            // Remember where the existing text ends so we append, not overwrite.
            dictationAnchor = draft.count
            speech.start()
        }
    }

    /// Replaces the dictated tail of `draft` with the latest transcript.
    private func applyTranscript(_ transcript: String) {
        guard speech.isRecording else { return }
        let prefix = String(draft.prefix(dictationAnchor))
        let separator = prefix.isEmpty || prefix.hasSuffix(" ") || prefix.hasSuffix("\n") ? "" : " "
        draft = prefix + separator + transcript
    }

    /// Stops recording (if any) and writes the draft, price and payment method
    /// back onto the session.
    private func stopAndPersist() {
        speech.stop()
        seance.note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        seance.priceCHF = priceCHF
        seance.paymentMethod = paymentMethod?.rawValue ?? ""
        // Flush explicite : sans ça le résumé/prix/paiement n'était pas écrit sur
        // disque avant un kill de l'app (swipe) et la séance se retrouvait sans
        // résumé, voire de nouveau "planifiée".
        try? context.save()
        // Reflect the finished session / updated summary in the home-screen widgets.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Waveform

/// Lightweight rolling bar visualization of the mic input levels.
private struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .foregroundStyle(.tint)
                        .frame(height: max(2, level * proxy.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    SeanceSummaryEditorView(
        seance: Seance(
            serviceName: "Thérapie Émotionnelle",
            durationMinutes: 60,
            priceCHF: 80,
            status: "terminee"
        ),
        language: "fr"
    )
    .modelContainer(for: [Client.self, Seance.self], inMemory: true)
}
