//
//  SettingsView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings sheet: appearance (theme) and language.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Contexte SwiftData, pour lire toutes les données lors de l'export.
    @Environment(\.modelContext) private var context

    // @AppStorage persists the choice and refreshes the UI live.
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: String = "fr"

    /// Re-shows the first-launch intro on demand (without touching the seen flag).
    @State private var showTutorial = false
    /// Requests the guided spotlight tour; ContentView starts it from the home.
    @AppStorage("pendingTour") private var pendingTour = false

    /// URL du fichier d'export généré, déclenche la feuille de partage quand non nil.
    @State private var exportFile: ExportFile?
    /// Message d'erreur d'export à afficher (alerte), nil si tout va bien.
    @State private var exportErrorMessage: String?

    /// Présente le sélecteur de fichier pour l'import quand vrai.
    @State private var showImporter = false
    /// Message de succès d'import (résumé), déclenche l'alerte quand non nil.
    @State private var importSuccessMessage: String?
    /// Message d'erreur d'import à afficher (alerte), nil si tout va bien.
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence") {
                    Picker("Thème", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                }

                Section("Langue") {
                    Picker("Langue", selection: $appLanguage) {
                        // Language names stay in their own language (not translated).
                        Text(verbatim: "Français").tag("fr")
                        Text(verbatim: "Português").tag("pt")
                    }
                }

                Section("Forfaits") {
                    NavigationLink {
                        ForfaitsView()
                    } label: {
                        Label("Mes forfaits", systemImage: "tag")
                    }
                }

                GoogleCalendarSection()

                Section("Données") {
                    Button {
                        exportData()
                    } label: {
                        Label("Exporter mes données", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Importer des données", systemImage: "square.and.arrow.down")
                    }
                }

                Section("Aide") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Centre d'aide", systemImage: "questionmark.circle")
                    }
                    Button {
                        showTutorial = true
                    } label: {
                        Label("Revoir le tutoriel", systemImage: "play.circle")
                    }
                    Button {
                        // Closes Settings, then ContentView starts the spotlight tour.
                        pendingTour = true
                        dismiss()
                    } label: {
                        Label("Visite guidée de l'app", systemImage: "hand.point.up.left")
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showTutorial) {
                OnboardingView { showTutorial = false }
            }
            // Feuille de partage du fichier d'export (pilotée par l'item URL).
            .sheet(item: $exportFile) { file in
                ActivityView(items: [file.url])
            }
            .alert(
                "Export impossible",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { if !$0 { exportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(verbatim: exportErrorMessage ?? "")
            }
            // Sélecteur de fichier pour l'import (uniquement des fichiers JSON).
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Import réussi",
                isPresented: Binding(
                    get: { importSuccessMessage != nil },
                    set: { if !$0 { importSuccessMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importSuccessMessage = nil }
            } message: {
                Text(verbatim: importSuccessMessage ?? "")
            }
            .alert(
                "Import impossible",
                isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importErrorMessage = nil }
            } message: {
                Text(verbatim: importErrorMessage ?? "")
            }
        }
    }

    // MARK: - Export des données

    /// Génère le fichier JSON via `DataExportService` puis présente la feuille de
    /// partage. En cas d'échec, affiche une alerte (pas de crash).
    private func exportData() {
        do {
            exportFile = ExportFile(url: try DataExportService.exportAll(context: context))
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Import des données

    /// Traite le résultat du `.fileImporter` : lit l'URL choisie (en gérant le
    /// security-scoped resource, requis pour les fichiers hors sandbox de l'app),
    /// lance l'upsert via `DataImportService`, puis affiche le résumé ou l'erreur.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }

            // L'URL du fileImporter pointe souvent hors du conteneur de l'app
            // (iCloud Drive, Fichiers...) : il faut demander l'accès sécurisé
            // avant de lire, puis le relâcher ensuite.
            let needsScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let summary = try DataImportService.importAll(from: url, context: context)
                importSuccessMessage = importSummaryText(summary)
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    /// Met en forme le bilan d'import pour l'alerte de confirmation.
    private func importSummaryText(_ summary: DataImportService.ImportSummary) -> String {
        let clients = summary.clientsInserted + summary.clientsUpdated
        let seances = summary.seancesInserted + summary.seancesUpdated
        let forfaits = summary.forfaitsInserted + summary.forfaitsUpdated
        let notes = summary.notesInserted + summary.notesUpdated
        return String(
            localized: "\(clients) clients, \(seances) séances, \(forfaits) forfaits, \(notes) notes importés."
        )
    }
}

/// Wrapper `UIActivityViewController` pour partager le fichier d'export.
/// (`ShareLink` ne prend qu'un seul style de présentation : on garde une feuille
/// de partage classique, robuste et déjà familière pour Marta.)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Petit wrapper Identifiable pour piloter `.sheet(item:)` avec l'URL du fichier
/// d'export (évite une conformance globale `URL: Identifiable`).
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    SettingsView()
        .environmentObject(GoogleCalendarService())
}
