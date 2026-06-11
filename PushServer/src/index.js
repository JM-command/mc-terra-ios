// MCTerra push-to-start server
//
// Relays APNs "push-to-start" Live Activity pushes at scheduled session times,
// so the lock-screen timer appears on its own without the app being open.
//
// The iOS app is the source of truth: it POSTs /sync with its current
// pushToStart token + the full list of upcoming sessions. We store that, and a
// 30s tick fires a push for each session as its time arrives.
//
// Env (see README):
//   APP_TOKEN        shared token the app must send (x-app-token)
//   APNS_KEY_PATH    path to the AuthKey_XXXX.p8 file
//   APNS_KEY_ID      the key id (10 chars)
//   APNS_TEAM_ID     Apple team id (CJKS93L92T)
//   APNS_BUNDLE_ID   ch.irixiagroup.MCTerra
//   APNS_HOST        api.push.apple.com (prod / TestFlight) or
//                    api.sandbox.push.apple.com (Xcode dev builds)
//   PORT             default 8787
//   DATA_FILE        where to persist state (default ./data.json)

import express from "express";
import jwt from "jsonwebtoken";
import http2 from "node:http2";
import fs from "node:fs";

const PORT = process.env.PORT || 8787;
const APP_TOKEN = process.env.APP_TOKEN || "";
const APNS_KEY_PATH = process.env.APNS_KEY_PATH || "./AuthKey.p8";
const APNS_KEY_ID = process.env.APNS_KEY_ID || "";
const APNS_TEAM_ID = process.env.APNS_TEAM_ID || "CJKS93L92T";
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID || "ch.irixiagroup.MCTerra";
const APNS_HOST = process.env.APNS_HOST || "api.push.apple.com";
const DATA_FILE = process.env.DATA_FILE || "./data.json";

// ---- Persistent state: { token, schedules: [{id, fireAt, attributes, contentState, alert}], fired: [id] }

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(DATA_FILE, "utf8"));
  } catch {
    return { token: null, schedules: [], fired: [] };
  }
}

function saveState(state) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(state, null, 2));
  } catch (e) {
    console.error("saveState failed:", e.message);
  }
}

let state = loadState();

// ---- APNs auth (JWT, cached ~50 min)

let cachedJWT = null;
let cachedAt = 0;

function apnsToken() {
  const now = Date.now();
  if (cachedJWT && now - cachedAt < 50 * 60 * 1000) return cachedJWT;
  const key = fs.readFileSync(APNS_KEY_PATH, "utf8");
  cachedJWT = jwt.sign({ iss: APNS_TEAM_ID, iat: Math.floor(now / 1000) }, key, {
    algorithm: "ES256",
    header: { alg: "ES256", kid: APNS_KEY_ID },
  });
  cachedAt = now;
  return cachedJWT;
}

// ---- Send one push-to-start over HTTP/2

// Prod (TestFlight/App Store) and sandbox (Xcode dev builds) use different APNs
// hosts AND different device tokens. A token from one is rejected by the other
// with BadDeviceToken. We don't know which env the current token belongs to, so
// we try the configured host first and fall back to the other on BadDeviceToken.
const APNS_HOSTS = APNS_HOST.includes("sandbox")
  ? ["api.sandbox.push.apple.com", "api.push.apple.com"]
  : ["api.push.apple.com", "api.sandbox.push.apple.com"];

function postToHost(host, deviceToken, schedule) {
  return new Promise((resolve) => {
    const payload = JSON.stringify({
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event: "start",
        "content-state": schedule.contentState,
        "attributes-type": "SessionActivityAttributes",
        attributes: schedule.attributes,
        alert: schedule.alert || undefined,
      },
    });

    const client = http2.connect(`https://${host}`);
    client.on("error", (e) => {
      console.error(`[${host}] http2 error:`, e.message);
      resolve({ status: 0, body: e.message });
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsToken()}`,
      "apns-push-type": "liveactivity",
      "apns-topic": `${APNS_BUNDLE_ID}.push-type.liveactivity`,
      "apns-priority": "10",
      "content-type": "application/json",
    });

    let status = 0;
    let body = "";
    req.on("response", (h) => { status = h[":status"]; });
    req.setEncoding("utf8");
    req.on("data", (d) => { body += d; });
    req.on("end", () => {
      client.close();
      resolve({ status, body });
    });
    req.end(payload);
  });
}

async function sendPushToStart(deviceToken, schedule) {
  for (const host of APNS_HOSTS) {
    const { status, body } = await postToHost(host, deviceToken, schedule);
    if (status === 200) {
      console.log(`push ok: ${schedule.id} via ${host}`);
      return true;
    }
    // Only worth retrying on the other host when the token is for the wrong env.
    if (!body.includes("BadDeviceToken")) {
      console.error(`push failed ${status} via ${host}: ${body}`);
      return false;
    }
    console.warn(`BadDeviceToken via ${host}, trying next host`);
  }
  console.error(`push failed: token rejected by both APNs hosts (${schedule.id})`);
  return false;
}

// ---- Scheduler tick: fire any schedule whose time has arrived (and not yet fired)

function tick() {
  if (!state.token || !state.schedules?.length) return;
  const now = Date.now();
  for (const s of state.schedules) {
    const fireMs = new Date(s.fireAt).getTime();
    // Fire when due, within a 10-minute catch-up window, once only.
    if (now >= fireMs && now - fireMs < 10 * 60 * 1000 && !state.fired.includes(s.id)) {
      state.fired.push(s.id);
      saveState(state);
      sendPushToStart(state.token, s);
    }
  }
  // Trim fired ids that are no longer scheduled.
  const ids = new Set(state.schedules.map((s) => s.id));
  state.fired = state.fired.filter((id) => ids.has(id));
}

setInterval(tick, 30 * 1000);

// ---- HTTP

const app = express();
app.use(express.json({ limit: "256kb" }));

app.post("/sync", (req, res) => {
  if (!APP_TOKEN || req.headers["x-app-token"] !== APP_TOKEN) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  const { token, schedules } = req.body || {};
  if (typeof token !== "string" || !Array.isArray(schedules)) {
    return res.status(400).json({ error: "Bad request" });
  }
  // Keep "fired" only for ids that still exist, so re-synced sessions can re-fire
  // only if their id changed (edited sessions reuse the same id => stay fired
  // once started; that's fine, the timer is already running).
  const ids = new Set(schedules.map((s) => s.id));
  state = {
    token,
    schedules,
    fired: (state.fired || []).filter((id) => ids.has(id)),
  };
  saveState(state);
  res.json({ ok: true, count: schedules.length });
});

app.get("/health", (_req, res) => res.json({ ok: true, schedules: state.schedules.length }));

app.listen(PORT, () => console.log(`MCTerra push server on :${PORT} (APNs ${APNS_HOST})`));
