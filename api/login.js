// Log in to an existing account. Returns a session token.
import { verifyUser, createSession } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  const body = req.body || {};
  const username = String(body.username || "").trim();
  const password = String(body.password || "");
  if (!username || !password) return res.status(400).json({ error: "bad_input" });
  try {
    const u = await verifyUser(username, password);
    if (!u) return res.status(401).json({ error: "invalid", message: "اسم المستخدم أو كلمة السر غير صحيحة." });
    const session = await createSession(u.username);
    return res.status(200).json({ ok: true, session, username: u.username });
  } catch (e) {
    return res.status(500).json({ error: "login_failed", detail: String(e) });
  }
}
