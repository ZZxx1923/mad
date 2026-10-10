// Create a new account. Returns a session token.
import { createUser, createSession } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  const body = req.body || {};
  const username = String(body.username || "").trim();
  const password = String(body.password || "");
  if (username.length < 3 || password.length < 4) {
    return res.status(400).json({ error: "bad_input", message: "اسم المستخدم 3 أحرف فأكثر، وكلمة السر 4 فأكثر." });
  }
  if (!/^[A-Za-z0-9_.-]+$/.test(username)) {
    return res.status(400).json({ error: "bad_username", message: "اسم المستخدم: حروف وأرقام إنجليزية فقط." });
  }
  try {
    const r = await createUser(username, password);
    if (r.error === "exists") return res.status(409).json({ error: "exists", message: "اسم المستخدم محجوز، اختر غيره." });
    const session = await createSession(r.username);
    return res.status(200).json({ ok: true, session, username: r.username });
  } catch (e) {
    return res.status(500).json({ error: "signup_failed", detail: String(e) });
  }
}
