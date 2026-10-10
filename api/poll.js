// Agent -> server. Fetches the next command for ITS device (scoped to the agent's account).
import { popCommand, userFromToken } from "./_lib/kv.js";

export default async function handler(req, res) {
  const user = await userFromToken(req.headers["x-agent-token"]);
  if (!user) return res.status(401).json({ error: "unauthorized" });

  const deviceId = String((req.query && req.query.deviceId) || req.headers["x-device-id"] || "pc");
  try {
    const cmd = await popCommand(user, deviceId);
    return res.status(200).json({ command: cmd || null });
  } catch (e) {
    return res.status(500).json({ error: "poll_failed", detail: String(e) });
  }
}
