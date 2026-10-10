// Phone -> server. Returns all known devices (with online state) and an optional command result.
import { listDevices, getResult } from "./_lib/kv.js";

export default async function handler(req, res) {
  const password = req.headers["x-ui-password"];
  if (!process.env.UI_PASSWORD || password !== process.env.UI_PASSWORD) {
    return res.status(401).json({ error: "unauthorized" });
  }

  try {
    const devices = await listDevices();
    let result = null;
    const id = req.query && req.query.id;
    if (id) result = await getResult(id);
    return res.status(200).json({ devices, result });
  } catch (e) {
    return res.status(500).json({ error: "status_failed", detail: String(e) });
  }
}
