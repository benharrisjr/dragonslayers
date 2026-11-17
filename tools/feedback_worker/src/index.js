// Relay for the in-game bug report form (autoloads/feedback_reporter.gd).
// The game POSTs plain multipart fields to /report; this Worker validates them,
// rate-limits per IP, builds the Discord embed and forwards it to the webhook
// held in the DISCORD_WEBHOOK_URL secret. The game never sees the webhook.

const CATEGORIES = {
  bug: { label: "Bug", color: 0xe05a47 },
  feedback: { label: "Feedback", color: 0x4f8fe0 },
  idea: { label: "Idea", color: 0x5cc26a },
};
const MAX_MESSAGE = 2000;
const MAX_FIELD = 1024;
const MAX_SCREENSHOT = 6 * 1024 * 1024;
const MAX_LOG = 512 * 1024;
// Context keys shown as embed fields, in this order: [key, label, inline].
const CONTEXT_FIELDS = [
  ["version", "Version", true],
  ["build", "Build", true],
  ["slot", "Slot", true],
  ["run", "Run", false],
  ["difficulty", "Difficulty", true],
  ["seed", "Seed", true],
  ["time", "Run Time", true],
  ["party", "Party", false],
  ["scene", "Scene", false],
  ["platform", "Platform", true],
  ["renderer", "Renderer", true],
  ["window", "Window", true],
  ["steam", "Steam", true],
];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/report") return text("Not found", 404);
    if (request.method !== "POST") return text("Method not allowed", 405);
    if (request.headers.get("X-Game-Key") !== env.GAME_KEY) return text("Forbidden", 403);
    const length = Number(request.headers.get("Content-Length") || 0);
    if (length > Number(env.MAX_BODY_BYTES || 8000000)) return text("Too large", 413);

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (env.RATE_LIMITER) {
      const { success } = await env.RATE_LIMITER.limit({ key: ip });
      if (!success) return text("Too many reports", 429);
    }

    let form;
    try {
      form = await request.formData();
    } catch {
      return text("Bad form", 400);
    }

    const category = CATEGORIES[String(form.get("category") || "")];
    if (!category) return text("Bad category", 400);
    const message = defang(String(form.get("message") || "").trim());
    if (message.length < 1 || message.length > MAX_MESSAGE) return text("Bad message", 400);

    let context = {};
    try {
      const parsed = JSON.parse(String(form.get("context") || "{}"));
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) context = parsed;
    } catch {
      // A report without context is still worth having.
    }

    const files = [];
    const screenshot = form.get("screenshot");
    if (isFile(screenshot)) {
      if (screenshot.size > MAX_SCREENSHOT) return text("Screenshot too large", 413);
      const bytes = new Uint8Array(await screenshot.arrayBuffer());
      if (!isPng(bytes)) return text("Screenshot must be PNG", 400);
      files.push({ name: "screenshot.png", type: "image/png", bytes });
    }
    const log = form.get("log");
    if (isFile(log)) {
      if (log.size > MAX_LOG) return text("Log too large", 413);
      files.push({ name: "log.txt", type: "text/plain", bytes: new Uint8Array(await log.arrayBuffer()) });
    }

    const firstLine = message.split("\n")[0];
    const embed = {
      title: clip(`[${category.label}] ${firstLine}`, 256),
      description: message,
      color: category.color,
      fields: CONTEXT_FIELDS.filter(([key]) => context[key] !== undefined && String(context[key]) !== "")
        .map(([key, name, inline]) => ({ name, value: clip(defang(String(context[key])), MAX_FIELD), inline })),
      footer: { text: clip(`v${defang(String(context.version || "?"))}`, 2048) },
      timestamp: new Date().toISOString(),
    };
    if (files.some((f) => f.name === "screenshot.png")) embed.image = { url: "attachment://screenshot.png" };

    const payload = {
      username: "Game Feedback",
      embeds: [embed],
      allowed_mentions: { parse: [] },
      attachments: files.map((f, i) => ({ id: i, filename: f.name })),
    };
    // A forum channel's webhook must open a thread per post: each report
    // becomes its own forum post titled like the embed.
    if (env.FORUM_CHANNEL === "true") payload.thread_name = clip(`[${category.label}] ${firstLine}`, 100);

    let res = await postToDiscord(env, payload, files);
    if (!res.ok) {
      let body = await res.text();
      // The webhook was moved to a forum channel without FORUM_CHANNEL set:
      // retry once as a thread rather than dropping the report.
      if (res.status === 400 && body.includes('"code": 220001') && !payload.thread_name) {
        payload.thread_name = clip(`[${category.label}] ${firstLine}`, 100);
        res = await postToDiscord(env, payload, files);
        body = res.ok ? "" : await res.text();
      }
      if (!res.ok) {
        console.log("discord rejected", res.status, body);
        return text("Upstream error", res.status === 429 ? 429 : 502);
      }
    }
    return text("ok", 200);
  },
};

function postToDiscord(env, payload, files) {
  const out = new FormData();
  out.append("payload_json", JSON.stringify(payload));
  files.forEach((f, i) => out.append(`files[${i}]`, new Blob([f.bytes], { type: f.type }), f.name));
  return fetch(env.DISCORD_WEBHOOK_URL, { method: "POST", body: out });
}

function text(body, status) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain" } });
}

function isFile(v) {
  return v && typeof v === "object" && typeof v.arrayBuffer === "function";
}

function isPng(b) {
  return b.length > 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47;
}

function clip(s, n) {
  return s.length > n ? s.slice(0, n - 1) + "…" : s;
}

// allowed_mentions already stops pings; this also keeps them from rendering
// as mentions, and breaks masked links.
function defang(s) {
  return s.replace(/@(everyone|here)/gi, "@​$1").replace(/<(@[!&]?|#)(\d+)>/g, "<​$1$2>");
}
