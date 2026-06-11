# MC-TERRA

Application iOS native pour la gestion d'un cabinet de coaching : clients, séances, agenda, comptabilité, le tout piloté par un assistant IA en langage naturel. Conçue local-first, pensée pour une utilisatrice unique non technique.

> Projet personnel / démo portfolio. Application réelle en production pour un cabinet de coaching.

## Aperçu

MC-TERRA remplace WhatsApp + agenda papier + carnet de notes par une seule app. On tape (ou on dicte) une phrase comme « déplace la séance de Maria à 16h » et l'assistant IA s'en occupe : il modifie la séance, replanifie le rappel, met à jour Google Calendar et le timer de l'écran verrouillé.

## Fonctionnalités

- **Assistant IA en langage naturel** : barre de commande Claude (tool-calling) qui crée, modifie et annule des séances, avec dictée vocale FR/PT.
- **Clients** : fiches complètes, import de contacts, raccourci WhatsApp, e-mail et adresse avec autocomplétion mondiale.
- **Notes par client** : journal horodaté (saisie manuelle ou IA) avec éditeur plein écran.
- **Séances** : forfaits éditables, encaissement, statut « client absent », accès direct aux séances du jour.
- **Agenda** : vue calendrier + synchronisation bidirectionnelle Google Calendar (lien Meet auto pour le distanciel).
- **Comptabilité** : revenus par mois et par année, export CSV / PDF.
- **Live Activity & push-to-start** : le timer de séance s'allume seul sur l'écran verrouillé à l'heure prévue, via un serveur APNs.
- **Backup** : export / import de toutes les données en JSON.
- **Confort** : i18n FR / PT-PT / EN, thème clair/sombre, onboarding et visite guidée, Face ID.

## Stack

- **App** : Swift, SwiftUI, SwiftData (local-first), ActivityKit, WidgetKit, MapKit, Speech.
- **IA** : API Claude (Anthropic) via un proxy Cloudflare Worker qui garde la clé côté serveur.
- **Push-to-start** : serveur Node.js (APNs HTTP/2, JWT ES256) piloté par PM2.
- **Intégrations** : Google Calendar (OAuth), Google Sign-In.

## Architecture

```
MCTerra/            App iOS (SwiftUI + SwiftData)
  App/              Point d'entrée, routing deep-link
  Models/           Client, Seance, Forfait, Note (schéma partagé app + widget)
  Services/         IA, push-to-start, Google Calendar, notifications, export
  Views/            Accueil, clients, séances, agenda, comptabilité, réglages
MCTerraWidgets/     Live Activity + widgets (mêmes modèles via App Group)
Proxy/              Cloudflare Worker (proxy API Claude, clé côté serveur)
PushServer/         Serveur APNs push-to-start (Node.js + PM2)
```

Choix structurants : identité stable par `uuid` sur chaque modèle (deep links, export/import idempotent, base pour une future sync), store SwiftData partagé entre l'app et le widget via App Group, secrets jamais embarqués côté client.

## Configuration

Les fichiers de configuration contenant des secrets sont gitignorés. Pour builder, copier les modèles et renseigner les valeurs :

```bash
cp config-templates/AIConfig.swift.example       MCTerra/Services/AI/AIConfig.swift
cp config-templates/PushConfig.swift.example     MCTerra/Services/Push/PushConfig.swift
cp config-templates/ecosystem.config.cjs.example PushServer/ecosystem.config.cjs
```

Le proxy IA (`Proxy/`) et le serveur push (`PushServer/`) lisent leurs secrets via les variables d'environnement (`wrangler secret put`, PM2 env), jamais en dur dans le code.
