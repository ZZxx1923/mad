// Agent -> server. Registers/refreshes this device so the phone can list it.
import { registerDevice } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const token = req.headers["x-agent-token"];
  if (!process.env.AGENT_TOKEN || token !== process.env.AGENT_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const body = req.body || {};
  const deviceId = String(body.deviceId || body.hostname || "pc");
  try {
    await registerDevice(deviceId, { name: body.hostname || deviceId, os: body.os || "" });
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: "heartbeat_failed", detail: String(e) });
  }
}
