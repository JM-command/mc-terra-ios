# Changelog

Toutes les modifications notables de l'app MC-TERRA sont documentées ici.

## [1.0.0] - 2026-06-11 10:00

### Phase 0 : Fondations

- **Ajouté** : app SwiftUI native, local-first (SwiftData), App Group `group.ch.irixiagroup.MCTerra` partagé app + widget
- **Ajouté** : onboarding premier lancement + visite guidée spotlight
- **Ajouté** : internationalisation FR / PT-PT / EN (String Catalog)
- **Ajouté** : thème clair/sombre/système, Face ID sur les suppressions

### Phase 1 : Clients et séances

- **Ajouté** : fiches clients (coordonnées, langue, import contacts, raccourci WhatsApp)
- **Ajouté** : séances avec forfaits éditables, durée, statut, moyen de paiement
- **Ajouté** : flux "Terminer la séance" avec résumé + encaissement
- **Ajouté** : comptabilité par mois et par année (export CSV / PDF)

### Phase 2 : Assistant IA

- **Ajouté** : barre de commande pilotée par Claude (tool-calling) qui crée, modifie et annule des séances
- **Ajouté** : proxy Cloudflare Worker gardant la clé API côté serveur
- **Ajouté** : dictée vocale (reconnaissance FR/PT) pour piloter l'assistant

### Phase 3 : Agenda et Google Calendar

- **Ajouté** : agenda style calendrier + synchronisation bidirectionnelle Google Calendar
- **Ajouté** : lien Google Meet automatique pour les séances en ligne

### Phase 4 : Live Activity et push-to-start

- **Ajouté** : Live Activity (timer de séance) + widgets + deep links `mcterra://`
- **Ajouté** : serveur push-to-start (APNs) démarrant le timer sur l'écran verrouillé à l'heure de la séance
- **Corrigé** : bascule automatique APNs production / sandbox selon le build (token sandbox rejeté en production)

### Phase 5 : Finitions avant lancement

- **Ajouté** : navigation par deep link depuis les notifications et la Live Activity vers la séance concernée
- **Ajouté** : carte "Séance en cours" cliquable sur l'accueil
- **Ajouté** : raccourci "Séances du jour", statut "Client absent" (no-show)
- **Ajouté** : système de notes horodatées par client (auteur Marta ou IA) avec éditeur plein écran
- **Ajouté** : champs client e-mail + adresse avec autocomplétion mondiale (MapKit)
- **Ajouté** : export / import des données en JSON (backup et restauration locale)
- **Corrigé** : persistance du statut "terminé" perdue après fermeture forcée de l'app
- **Corrigé** : resynchronisation du serveur push à chaque création / modification / suppression de séance
- **Corrigé** : suppression d'une séance retirant aussi l'évènement Google Calendar
