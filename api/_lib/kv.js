// Shared Redis data layer (multi-user, multi-device).
// Each user has their own namespace: devices, command queues, agent token.
// Files under api/_lib are NOT turned into routes by Vercel (underscore prefix).
import Redis from "ioredis";
import crypto from "crypto";

let _client = null;
function getClient() {
  if (_client) return _client;
  const url = process.env.REDIS_URL || process.env.KV_URL || process.env.UPSTASH_REDIS_URL;
  if (!url) {
    throw new Error("REDIS_URL is not set. Connect a Redis database in Vercel (Storage).");
  }
  _client = new Redis(url, { maxRetriesPerRequest: 3 });
  _client.on("error", () => {});
  return _client;
}

const ONLINE_MS = 30000;
const SESSION_TTL = 60 * 60 * 24 * 60; // 60 days

// ------------------------- users / auth -------------------------
function hashPw(pw, salt) {
  return crypto.scryptSync(String(pw), salt, 32).toString("hex");
}

export async function createUser(username, password) {
  const c = getClient();
  const u = String(username).toLowerCase();
  if (await c.exists(`user:${u}`)) return { error: "exists" };
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = hashPw(password, salt);
  const token = crypto.randomBytes(24).toString("base64url");
  await c.set(`user:${u}`, JSON.stringify({ salt, hash, token, name: username }));
  await c.set(`tok:${token}`, u);
  return { username: u, token };
}

export async function verifyUser(username, password) {
  const c = getClient();
  const u = String(username).toLowerCase();
  const raw = await c.get(`user:${u}`);
  if (!raw) return null;
  const d = JSON.parse(raw);
  const h = hashPw(password, d.salt);
  if (h.length !== d.hash.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(h), Buffer.from(d.hash))) return null;
  return { username: u, token: d.token };
}

export async function getUserToken(username) {
  const c = getClient();
  const raw = await c.get(`user:${String(username).toLowerCase()}`);
  return raw ? JSON.parse(raw).token : null;
}

export async function createSession(username) {
  const c = getClient();
  const s = crypto.randomBytes(24).toString("base64url");
  await c.set(`sess:${s}`, String(username).toLowerCase(), "EX", SESSION_TTL);
  return s;
}

export async function userFromSession(session) {
  if (!session) return null;
  return await getClient().get(`sess:${session}`);
}

export async function userFromToken(token) {
  if (!token) return null;
  return await getClient().get(`tok:${token}`);
}

// ------------------------- devices (per user) -------------------------
export async function registerDevice(user, deviceId, info) {
  const c = getClient();
  const data = { name: info.name || deviceId, os: info.os || "", ts: Date.now() };
  await c.hset(`dev:${user}`, deviceId, JSON.stringify(data));
}

export async function listDevices(user) {
  const c = getClient();
  const all = await c.hgetall(`dev:${user}`);
  const out = [];
  for (const [id, v] of Object.entries(all || {})) {
    try {
      const d = JSON.parse(v);
      out.push({ id, name: d.name || id, os: d.os || "", ts: d.ts || 0, online: Date.now() - (d.ts || 0) < ONLINE_MS });
    } catch {}
  }
  out.sort((a, b) => (b.ts || 0) - (a.ts || 0));
  return out;
}

export async function removeDevice(user, deviceId) {
  const c = getClient();
  await c.hdel(`dev:${user}`, deviceId);
  await c.del(`cmd:${user}:${deviceId}`);
}

// ------------------------- commands (per user+device) -------------------------
export async function pushCommand(user, deviceId, cmd) {
  const c = getClient();
  const key = `cmd:${user}:${deviceId}`;
  await c.lpush(key, JSON.stringify(cmd));
  await c.ltrim(key, 0, 49);
}

export async function popCommand(user, deviceId) {
  const c = getClient();
  const v = await c.rpop(`cmd:${user}:${deviceId}`);
  return v ? JSON.parse(v) : null;
}

// dedup: returns true if the SAME action for the same device was sent in the last `seconds`
export async function isDuplicate(user, deviceId, action, seconds = 5) {
  const c = getClient();
  const r = await c.set(`recent:${user}:${deviceId}:${action}`, "1", "EX", seconds, "NX");
  return r === null;
}

// ------------------------- results (global by unique id) -------------------------
export async function setResult(id, result) {
  await getClient().set(`res:${id}`, JSON.stringify(result), "EX", 300);
}

export async function getResult(id) {
  const v = await getClient().get(`res:${id}`);
  return v ? JSON.parse(v) : null;
}

// temporary diagnostic: list accounts and which have devices
export async function debugDump() {
  const c = getClient();
  const userKeys = await c.keys("user:*");
  const users = userKeys.map((k) => k.slice(5));
  const devKeys = await c.keys("dev:*");
  const devices = {};
  for (const k of devKeys) {
    const h = await c.hgetall(k);
    const list = [];
    for (const [id, v] of Object.entries(h || {})) {
      try { const d = JSON.parse(v); list.push({ id, name: d.name, online: Date.now() - (d.ts || 0) < 30000 }); } catch {}
    }
    devices[k.slice(4)] = list;
  }
  return { users, devices };
}
