// Phone -> server. Removes a device from the list (e.g. an old/renamed PC).
import { removeDevice } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const password = req.headers["x-ui-password"];
  if (!process.env.UI_PASSWORD || password !== process.env.UI_PASSWORD) {
    return res.status(401).json({ error: "unauthorized" });
  }

  const body = req.body || {};
  const deviceId = String(body.deviceId || "");
  if (!deviceId) return res.status(400).json({ error: "no_device" });

  try {
    await removeDevice(deviceId);
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: "forget_failed", detail: String(e) });
  }
}
