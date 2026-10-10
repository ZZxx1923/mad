// Agent -> server. Registers/refreshes this device under the agent's account.
import { registerDevice, userFromToken } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const user = await userFromToken(req.headers["x-agent-token"]);
  if (!user) return res.status(401).json({ error: "unauthorized" });

  const body = req.body || {};
  const deviceId = String(body.deviceId || body.hostname || "pc");
  try {
    await registerDevice(user, deviceId, { name: body.hostname || deviceId, os: body.os || "" });
    return res.status(200).json({ ok: true, user });
  } catch (e) {
    return res.status(500).json({ error: "heartbeat_failed", detail: String(e) });
  }
}
