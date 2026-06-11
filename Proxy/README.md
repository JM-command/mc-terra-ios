# MCTerra AI proxy

Petit Cloudflare Worker qui sert de portier entre l'app iOS de Marta et l'API Anthropic.
La vraie clé API vit ici (secret côté serveur), jamais dans l'app.

## Déploiement (à faire une fois)

Dans un terminal, depuis ce dossier `Proxy/` :

```bash
# 1. Se connecter à Cloudflare (ouvre le navigateur)
npx wrangler login

# 2. Créer le KV pour le compteur quotidien (garde-fou facture)
npx wrangler kv namespace create RATE
#   -> copie l'id affiché dans wrangler.toml (remplace PASTE_KV_ID_HERE)

# 3. Mettre les 2 secrets (il demande la valeur après chaque commande)
npx wrangler secret put ANTHROPIC_API_KEY
#   -> colle ta NOUVELLE clé sk-ant-... (jamais l'ancienne grillée)
npx wrangler secret put APP_TOKEN
#   -> colle un mot de passe au hasard, ex: openssl rand -hex 24

# 4. Déployer
npx wrangler deploy
#   -> note l'URL affichée, ex: https://mcterra-ai.TONCOMPTE.workers.dev
```

## Ce dont l'app a besoin

Deux infos à me donner après le déploiement :

- **URL du worker** (ex: `https://mcterra-ai.toncompte.workers.dev`)
- **APP_TOKEN** (le mot de passe au hasard de l'étape 3)

L'app appellera `POST <URL>/v1/messages` avec le header `x-app-token: <APP_TOKEN>`.

## Tester vite fait (optionnel)

```bash
curl -s https://mcterra-ai.TONCOMPTE.workers.dev/v1/messages \
  -H "x-app-token: TON_APP_TOKEN" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":64,"messages":[{"role":"user","content":"dis bonjour"}]}'
```

Si tu vois une réponse JSON de Claude, le proxy marche.

## Garde-fou facture

`DAILY_LIMIT = "300"` dans `wrangler.toml` = le worker refuse après 300 requêtes/jour.
Largement assez pour une coach. Monte/descends à ta guise, ou enlève le bloc `[vars]` + le KV pour pas de limite.
