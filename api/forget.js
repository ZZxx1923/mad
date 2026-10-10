// Phone -> server. Removes one of the user's own devices from the list.
import { removeDevice, userFromSession } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const user = await userFromSession(req.headers["x-session"]);
  if (!user) return res.status(401).json({ error: "unauthorized" });

  const body = req.body || {};
  const deviceId = String(body.deviceId || "");
  if (!deviceId) return res.status(400).json({ error: "no_device" });

  try {
    await removeDevice(user, deviceId);
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(500).json({ error: "forget_failed", detail: String(e) });
  }
}
