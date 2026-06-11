//
//  MCTerraApp.swift
//  MCTerra
//
//  Created by Jaime Coelho on 05.06.2026.
//

import SwiftUI
import SwiftData
import GoogleSignIn
import WidgetKit
import UserNotifications

/// Reçoit les taps sur les notifications locales (corps, boutons d'action) et les
/// convertit en deep link `mcterra://` rediffusé via `NotificationCenter`. Sans ce
/// delegate, iOS ouvrait l'app sans transporter l'UUID de la séance, d'où l'arrivée
/// systématique sur l'accueil. Le routage final est fait par le `DeepLinkRouter`
/// déjà injecté dans le `WindowGroup` (voir `.onReceive` plus bas).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // On devient le delegate pour intercepter les taps sur les notifications.
        UNUserNotificationCenter.current().delegate = self
        // Enregistre les catégories (boutons "Voir la séance" / "Démarrer").
        NotificationService.setupCategories()
        return true
    }

    /// Tap sur une notification (corps ou bouton d'action). On extrait le deep link
    /// du `userInfo` et on le rediffuse pour que le `DeepLinkRouter` navigue.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let link = userInfo["deepLink"] as? String, var url = URL(string: link) {
            // Le bouton "Démarrer" pointe explicitement hors flux finish (finish=0)
            // pour ouvrir la séance et lancer le chrono, pas l'écran de paiement.
            if response.actionIdentifier == "DEMARRER_SEANCE",
               let withFinish = URL(string: link + (link.contains("?") ? "&finish=0" : "?finish=0")) {
                url = withFinish
            }
            NotificationCenter.default.post(name: .mcterraDeepLink, object: url)
        }
        completionHandler()
    }

    /// Notification reçue alors que l'app est au premier plan : on l'affiche quand
    /// même (bannière + son) au lieu de la masquer silencieusement.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct MCTerraApp: App {
    // Pont vers le cycle de vie UIKit : permet de poser le delegate de notifications
    // dès le lancement (impossible depuis le pur SwiftUI App lifecycle).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Tracks the app's foreground/background state so we can refresh widgets.
    @Environment(\.scenePhase) private var scenePhase

    // Saved user choices, persisted on the device.
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appLanguage") private var appLanguage: String = "fr"
    // Calendar chosen in Settings; empty until the user picks one.
    @AppStorage("googleCalendarId") private var googleCalendarId: String = ""

    // Shared Google Calendar connection, injected into the view tree.
    @StateObject private var googleCalendar = GoogleCalendarService()
    // Parses incoming `mcterra://` deep links (from the widgets) into a route that
    // ContentView presents. Injected so any view can observe the current target.
    @StateObject private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Forces light/dark, or follows the system when .system.
                .preferredColorScheme(appTheme.colorScheme)
                // Drives the app language. Translations live in the String Catalog.
                .environment(\.locale, Locale(identifier: appLanguage))
                // Make the Google connection available to Settings and the agenda.
                .environmentObject(googleCalendar)
                // Make the deep-link target available to ContentView (and anyone else).
                .environmentObject(deepLinkRouter)
                // Routes incoming URLs: our own `mcterra://` deep links open a screen
                // via the router; everything else (notably the Google OAuth callback)
                // is forwarded to GoogleSignIn so its flow still completes.
                .onOpenURL { url in
                    if deepLinkRouter.handle(url) { return }
                    GIDSignIn.sharedInstance.handle(url)
                }
                // Deep links rediffusés depuis le delegate de notifications (taps
                // sur une notif ou ses boutons) et depuis l'intent "Démarrer" de la
                // Live Activity. On réutilise la MÊME instance que `.onOpenURL`, donc
                // la navigation passe par le même routeur que les liens entrants.
                .onReceive(NotificationCenter.default.publisher(for: .mcterraDeepLink)) { notif in
                    if let url = notif.object as? URL {
                        deepLinkRouter.handle(url)
                    }
                }
                // Restore the previous Google session, then pull the latest events.
                .task {
                    NotificationService.requestAuthorization()
                    // Refresh the smart daily/weekly reminders on launch.
                    let context = SharedModelContainer.shared.mainContext
                    // Seed the default forfaits on first launch (no-op afterwards).
                    Forfait.seedDefaultsIfNeeded(context)
                    DailyReminderService.scheduleTomorrowSummary(using: context)
                    DailyReminderService.scheduleStaleClientsNudge(using: context)
                    // Auto-start Live Activity at session time, via the push server.
                    PushToStartService.shared.startObserving()
                    PushToStartService.shared.sync(using: context)
                    await restoreAndSyncGoogle()
                }
                // Refresh the home-screen widgets whenever the app comes to the
                // foreground, so they reflect changes made while it was backgrounded.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        WidgetCenter.shared.reloadAllTimelines()
                        // Re-evaluate the smart reminders against the latest data.
                        let context = SharedModelContainer.shared.mainContext
                        DailyReminderService.scheduleTomorrowSummary(using: context)
                        DailyReminderService.scheduleStaleClientsNudge(using: context)
                        // Re-sync upcoming sessions to the push-to-start server.
                        PushToStartService.shared.sync(using: context)
                    }
                }
        }
        // Uses the SwiftData store backed by the App Group so the home-screen
        // widgets (which run in a separate process) read the same data.
        // ⚠️ Requires the "App Groups" capability `group.ch.irixiagroup.MCTerra`
        // on this target — see SharedModelContainer.swift.
        .modelContainer(SharedModelContainer.shared)
    }

    /// Restores any saved Google session and, when connected with a chosen
    /// calendar, imports the upcoming events. Failures are swallowed so a missing
    /// network or revoked access never blocks app launch.
    private func restoreAndSyncGoogle() async {
        await googleCalendar.restore()
        guard googleCalendar.isSignedIn, !googleCalendarId.isEmpty else { return }
        let context = SharedModelContainer.shared.mainContext
        try? await googleCalendar.import(into: context, calendarId: googleCalendarId)
    }
}
