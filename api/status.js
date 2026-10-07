// Phone -> server. Returns whether the PC is online and (optionally) a command's result.
import { getHeartbeat, getResult } from "./_lib/kv.js";

export default async function handler(req, res) {
  const password = req.headers["x-ui-password"];
  if (!process.env.UI_PASSWORD || password !== process.env.UI_PASSWORD) {
    return res.status(401).json({ error: "unauthorized" });
  }

  try {
    const hb = await getHeartbeat();
    const online = !!(hb && Date.now() - hb.ts < 30000); // online if seen in last 30s

    let result = null;
    const id = req.query.id;
    if (id) result = await getResult(id);

    return res.status(200).json({ online, heartbeat: hb, result });
  } catch (e) {
    return res.status(500).json({ error: "status_failed", detail: String(e) });
  }
}
