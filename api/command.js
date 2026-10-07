// Phone -> server. Queues a command for the PC agent to pick up.
import { pushCommand } from "./_lib/kv.js";

const ALLOWED = ["shutdown", "restart", "sleep", "lock", "logoff", "cancel", "wake"];

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "method_not_allowed" });
  }

  // Auth: the password you set in Vercel env vars, sent from the web UI.
  const password = req.headers["x-ui-password"];
  if (!process.env.UI_PASSWORD || password !== process.env.UI_PASSWORD) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const body = req.body || {};
  const action = body.action;
  if (!ALLOWED.includes(action)) {
    return res.status(400).json({ error: "bad_action" });
  }

  const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  const cmd = {
    id,
    action,
    delay: Number(body.delay) || 0,
    ts: Date.now(),
  };

  try {
    await pushCommand(cmd);
    return res.status(200).json({ ok: true, id });
  } catch (e) {
    return res.status(500).json({ error: "queue_failed", detail: String(e) });
  }
}
