# MCTerra Push Server

Relais APNs "push-to-start" : démarre la Live Activity (timer séance) toute seule à l'heure, sur le lock screen, sans ouvrir l'app.

## Ce dont tu as besoin (Apple)

1. Apple Developer → Certificates, IDs & Profiles → **Keys** → "+" → coche **Apple Push Notifications service (APNs)** → Register → **télécharge le `.p8`** (une seule fois) et note le **Key ID**.
2. Team ID = `CJKS93L92T`. Bundle id = `ch.irixiagroup.MCTerra`.
3. Dans Xcode (target MCTerra) → Signing & Capabilities → **+ Capability → Push Notifications**.

## Déploiement VYTEK (PM2)

```bash
# Copier le dossier PushServer/ sur VYTEK, et le .p8 dedans (ex: AuthKey.p8)
cd PushServer
npm install

# Variables (mets-les dans un ecosystem.config.cjs ou en env PM2)
export APP_TOKEN="$(openssl rand -hex 24)"     # note-le, il va dans l'app
export APNS_KEY_PATH="./AuthKey.p8"
export APNS_KEY_ID="XXXXXXXXXX"                 # le Key ID Apple
export APNS_TEAM_ID="CJKS93L92T"
export APNS_BUNDLE_ID="ch.irixiagroup.MCTerra"
export APNS_HOST="api.push.apple.com"           # TestFlight/prod (Xcode dev = api.sandbox.push.apple.com)
export PORT=8787

pm2 start src/index.js --name mcterra-push
pm2 save
```

Mets-le derrière ton reverse proxy / Cloudflare en HTTPS (ex: `https://mcterra-push.irixiagroup.ch`).

## Ce que l'app a besoin

Deux infos à coller dans `MCTerra/Services/Push/PushConfig.swift` :
- **URL** du serveur (HTTPS, sans slash final).
- **APP_TOKEN** (l'étape ci-dessus).

## Test

```bash
curl -s https://mcterra-push.TONDOMAINE/health
# -> { "ok": true, "schedules": N }
```

Puis dans l'app : crée une séance dans ~3 minutes, verrouille le téléphone, attends. La Live Activity doit apparaître seule.

## Pièges connus (Phase 3)

- **Date du timer fausse** = format du `startDate` dans le content-state. L'app l'envoie en secondes Unix. Si le timer déraille, c'est le 1er truc à changer (ISO8601).
- **Push refusé (400 BadDeviceToken / TopicDisallowed)** = mauvais `APNS_HOST` (sandbox vs prod) ou mauvais bundle id. TestFlight = prod.
- **Rien ne se passe** = le token pushToStart a tourné et l'app n'a pas resync. L'app resync au lancement + au retour de veille.
