// Agent -> server. The agent fetches the next command for ITS device.
import { popCommand } from "./_lib/kv.js";

export default async function handler(req, res) {
  const token = req.headers["x-agent-token"];
  if (!process.env.AGENT_TOKEN || token !== process.env.AGENT_TOKEN) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const deviceId = String((req.query && req.query.deviceId) || req.headers["x-device-id"] || "pc");
  try {
    const cmd = await popCommand(deviceId);
    return res.status(200).json({ command: cmd || null });
  } catch (e) {
    return res.status(500).json({ error: "poll_failed", detail: String(e) });
  }
}
