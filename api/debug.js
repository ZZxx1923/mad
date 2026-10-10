// TEMPORARY diagnostic endpoint. Remove after debugging.
import { debugDump } from "./_lib/kv.js";

export default async function handler(req, res) {
  if (!req.query || req.query.key !== "letmein-9271") {
    return res.status(401).json({ error: "nope" });
  }
  try {
    return res.status(200).json(await debugDump());
  } catch (e) {
    return res.status(500).json({ error: String(e) });
  }
}
