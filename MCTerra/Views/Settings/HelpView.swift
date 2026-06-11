//
//  HelpView.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI

// Help center: a list of simple articles. Each article opens a detail page
// with a short, non-technical explanation and a fake (non-interactive) mockup
// that imitates the real piece of UI, so Marta sees exactly what to tap
// without needing screenshots.

/// One help article: a title, a simple explanation, and a mockup to show.
struct HelpArticle: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let icon: String
    let explanation: LocalizedStringKey
    /// The fake UI piece shown at the bottom of the detail page.
    let mockup: AnyView
}

struct HelpView: View {
    // The full list, assembled from smaller groups. Splitting the array keeps
    // each computed property light for the Swift type-checker (avoids timeouts).
    private var articles: [HelpArticle] {
        basicsArticles + seanceArticles + agendaAndMoneyArticles
    }

    // MARK: - Basics (existing articles)

    private var basicsArticles: [HelpArticle] {
        [
            HelpArticle(
                title: "Dicter avec la voix",
                icon: "mic.fill",
                explanation: "En bas de l'écran d'accueil, touche le petit micro bleu, puis parle : ce que tu dis s'écrit tout seul. Important : la dictée écrit dans la langue choisie dans les Réglages. Pour dicter en portugais, mets d'abord l'application en portugais (Réglages → Langue).",
                mockup: AnyView(MockInputBar())
            ),
            HelpArticle(
                title: "Importer mes contacts",
                icon: "square.and.arrow.down",
                explanation: "Ouvre le menu : touche le bouton ☰ en haut à gauche, ou balaye l'écran depuis le bord gauche vers la droite. Dans le menu, touche « Importer contacts », puis choisis les personnes à ajouter.",
                mockup: AnyView(MockMenuRow(title: "Importer contacts", systemImage: "square.and.arrow.down"))
            ),
            HelpArticle(
                title: "Ajouter un client à la main",
                icon: "person.badge.plus",
                explanation: "Ouvre le menu (bouton ☰ en haut à gauche), touche « Nouveau client », écris le nom de la personne, puis touche « Enregistrer ». C'est tout.",
                mockup: AnyView(
                    VStack(spacing: 16) {
                        MockMenuRow(title: "Nouveau client", systemImage: "person.badge.plus")
                        MockTextField(placeholder: "Nom")
                        MockSaveButton()
                    }
                )
            ),
            HelpArticle(
                title: "Changer la langue ou le thème",
                icon: "globe",
                explanation: "Va dans les Réglages (bouton roue dentée). Sous « Langue », choisis Français ou Português. Sous « Apparence », choisis le thème clair, sombre ou système.",
                mockup: AnyView(
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Langue")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            MockPicker(options: ["Français", "Português"], selectedIndex: 0)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Thème")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            MockPicker(options: ["Clair", "Sombre", "Système"], selectedIndex: 2)
                        }
                    }
                )
            ),
            HelpArticle(
                title: "Me déplacer dans l'app",
                icon: "arrow.left.arrow.right",
                explanation: "Pour ouvrir le menu, touche le bouton ☰ en haut à gauche, ou balaye depuis le bord gauche vers la droite. Pour revenir à l'écran d'accueil, touche le bouton « Accueil » en bas à droite.",
                mockup: AnyView(
                    HStack(spacing: 24) {
                        MockHamburgerButton()
                        MockHomeButton()
                    }
                )
            )
        ]
    }

    // MARK: - Sessions (séances)

    private var seanceArticles: [HelpArticle] {
        [
            HelpArticle(
                title: "Créer et gérer une séance",
                icon: "calendar.badge.plus",
                explanation: "Ouvre la fiche d'un client, va sur l'onglet « Séances », puis touche « Nouvelle séance ». Choisis le forfait (le prix et la durée se remplissent tout seuls, tu peux les changer), règle la durée en heures et minutes, choisis le lieu (Cabinet ou Zoom), puis la date et l'heure. Touche « Enregistrer ».",
                mockup: AnyView(
                    VStack(spacing: 12) {
                        MockFormRow(title: "Forfait", value: "Thérapie Émotionnelle")
                        MockFormRow(title: "Durée", value: "1 h 00")
                        MockLocationRow(location: .cabinet)
                    }
                )
            ),
            HelpArticle(
                title: "Démarrer et terminer une séance",
                icon: "play.circle.fill",
                explanation: "Quand le rendez-vous arrive, ouvre la séance et touche « Démarrer la séance » : un minuteur se met à tourner. Il s'affiche aussi sur l'écran verrouillé du téléphone, avec un bouton pour mettre en marche (Play) et un pour arrêter (Stop), sans rouvrir l'application. À la fin, touche « Terminer la séance ».",
                mockup: AnyView(MockStartStopButtons())
            ),
            HelpArticle(
                title: "Noter le paiement",
                icon: "francsign.circle",
                explanation: "À la fin d'une séance, l'écran du résumé s'ouvre. Choisis comment la personne a payé : Twint, Carte ou Espèces. Tu peux aussi corriger le prix si besoin. Une séance gratuite peut rester sans paiement.",
                mockup: AnyView(MockPaymentSelector(selectedIndex: 0))
            )
        ]
    }

    // MARK: - Agenda, money, contact, widget

    private var agendaAndMoneyArticles: [HelpArticle] {
        [
            HelpArticle(
                title: "Voir l'agenda",
                icon: "calendar",
                explanation: "Ouvre l'Agenda depuis le menu. En haut, choisis « Mois » pour voir tout le mois (chaque jour montre des petites pastilles colorées, une par rendez-vous) ou « Jour » pour voir les séances d'une journée, l'une après l'autre selon l'heure. Touche une séance pour ouvrir sa fiche.",
                mockup: AnyView(MockAgendaDayCell())
            ),
            HelpArticle(
                title: "Connecter Google Agenda",
                icon: "calendar.badge.clock",
                explanation: "Va dans les Réglages, section « Google Agenda ». Touche « Connecter Google Agenda » et connecte-toi avec ton compte Google. Choisis ensuite l'agenda à utiliser, puis touche « Actualiser maintenant ». Tes rendez-vous Google apparaissent alors dans l'Agenda de l'application.",
                mockup: AnyView(
                    VStack(spacing: 12) {
                        MockMenuRow(title: "Connecter Google Agenda", systemImage: "calendar.badge.clock")
                        MockMenuRow(title: "Actualiser maintenant", systemImage: "arrow.clockwise")
                    }
                )
            ),
            HelpArticle(
                title: "Voir les revenus (Comptabilité)",
                icon: "chart.bar.fill",
                explanation: "Ouvre la Comptabilité depuis le menu. En haut, choisis le mois avec les flèches. Tu vois le total gagné et la répartition par moyen de paiement (Twint, Carte, Espèces). Pour garder une trace ou l'envoyer à ton comptable, touche « Exporter » et choisis CSV ou PDF.",
                mockup: AnyView(MockRevenueExport())
            ),
            HelpArticle(
                title: "Envoyer un message WhatsApp",
                icon: "message.fill",
                explanation: "Depuis la fiche d'un client (onglet « Actions ») ou depuis une séance, touche « Message WhatsApp ». Tu peux aussi choisir un message déjà prêt (rappel de rendez-vous, etc.). WhatsApp s'ouvre avec le message déjà écrit : il ne te reste qu'à l'envoyer.",
                mockup: AnyView(MockMenuRow(title: "Message WhatsApp", systemImage: "message.fill"))
            ),
            HelpArticle(
                title: "Ajouter un widget sur l'écran d'accueil",
                icon: "rectangle.3.group.fill",
                explanation: "Un widget est une petite vignette sur l'écran d'accueil du téléphone. Appuie longuement sur un endroit vide de l'écran d'accueil jusqu'à ce que les icônes bougent, touche le « + » en haut à gauche, cherche « MC-TERRA », puis choisis « Prochaine séance » ou « Revenus ». Touche « Ajouter le widget ».",
                mockup: AnyView(
                    VStack(spacing: 12) {
                        MockMenuRow(title: "Prochaine séance", systemImage: "calendar")
                        MockMenuRow(title: "Revenus", systemImage: "chart.bar.fill")
                    }
                )
            )
        ]
    }

    var body: some View {
        List(articles) { article in
            NavigationLink {
                HelpArticleDetailView(article: article)
            } label: {
                Label(article.title, systemImage: article.icon)
            }
        }
        .navigationTitle("Centre d'aide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Detail page for a single help article: explanation + static mockup.
struct HelpArticleDetailView: View {
    let article: HelpArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(article.explanation)
                    .font(.body)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Voici à quoi ça ressemble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    article.mockup
                }
            }
            .padding()
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
