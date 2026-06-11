// Modèle PM2 : copier en `ecosystem.config.cjs` (gitignoré) et remplir les secrets.
module.exports = {
  apps: [{
    name: "mcterra-push",
    script: "src/index.js",
    cwd: "/chemin/vers/mcterra-push",
    env: {
      PORT: "8788",
      APP_TOKEN: "VOTRE_APP_TOKEN",
      APNS_KEY_PATH: "./AuthKey.p8",
      APNS_KEY_ID: "VOTRE_KEY_ID",
      APNS_TEAM_ID: "VOTRE_TEAM_ID",
      APNS_BUNDLE_ID: "ch.exemple.MonApp",
      APNS_HOST: "api.push.apple.com",
      DATA_FILE: "/chemin/vers/mcterra-push/data.json"
    }
  }]
}
