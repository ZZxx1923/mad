// Phone -> server. Returns the user's own devices and an optional command result.
import { listDevices, getResult, userFromSession } from "./_lib/kv.js";

export default async function handler(req, res) {
  const user = await userFromSession(req.headers["x-session"]);
  if (!user) return res.status(401).json({ error: "unauthorized" });

  try {
    const devices = await listDevices(user);
    let result = null;
    const id = req.query && req.query.id;
    if (id) result = await getResult(id);
    return res.status(200).json({ devices, result });
  } catch (e) {
    return res.status(500).json({ error: "status_failed", detail: String(e) });
  }
}
