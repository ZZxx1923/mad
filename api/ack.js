// Agent -> server. Reports the result of a command so the phone can display it.
import { setResult } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "method_not_allowed" });
  }

  const token = req.headers["x-agent-token"];
  if (!process.env.AGENT_TOKEN || token !== process.env.AGENT_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const body = req.body || {};
  if (!body.id) {
    return res.status(400).json({ error: "no_id" });
  }

  try {
    await setResult(body.id, {
      status: body.status || "unknown",
      message: body.message || "",
      ts: Date.now(),
    });
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: "ack_failed", detail: String(e) });
  }
}
