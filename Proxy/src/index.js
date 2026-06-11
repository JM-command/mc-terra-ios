// MCTerra AI proxy — Cloudflare Worker
//
// Sits between Marta's iOS app and the Anthropic API so the real API key
// never lives in the app binary. The app calls THIS worker with a shared
// app token; the worker injects the real key and forwards to Claude.
//
// Secrets (set with `wrangler secret put`):
//   ANTHROPIC_API_KEY  — your real Anthropic key (sk-ant-...)
//   APP_TOKEN          — a random string the app must send to be allowed in
//
// Optional vars (in wrangler.toml [vars]):
//   DAILY_LIMIT        — max requests per day before the worker refuses (cost guard)

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export default {
  async fetch(request, env, ctx) {
    // Only accept POSTs to /v1/messages — everything else is a 404.
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/messages") {
      return json({ error: "Not found" }, 404);
    }

    // Gate: the app must present the shared token. No token, no entry.
    const token = request.headers.get("x-app-token");
    if (!env.APP_TOKEN || token !== env.APP_TOKEN) {
      return json({ error: "Unauthorized" }, 401);
    }

    // Cost guard: cap total requests per UTC day if DAILY_LIMIT is set.
    if (env.DAILY_LIMIT && env.RATE) {
      const day = new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
      const key = `count:${day}`;
      const current = parseInt((await env.RATE.get(key)) || "0", 10);
      if (current >= parseInt(env.DAILY_LIMIT, 10)) {
        return json({ error: "Daily limit reached" }, 429);
      }
      // Increment, expire after 48h so old days clean themselves up.
      ctx.waitUntil(env.RATE.put(key, String(current + 1), { expirationTtl: 172800 }));
    }

    // Read the app's body (a normal Anthropic messages request) and forward it,
    // adding the real key + version header server-side.
    let body;
    try {
      body = await request.text();
    } catch {
      return json({ error: "Bad request" }, 400);
    }

    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body,
    });

    // Pass Claude's response straight back to the app, untouched.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });
}
