// Shared Redis helper (multi-device). Works with any REDIS_URL from Vercel Storage.
// Files under api/_lib are NOT turned into routes by Vercel (underscore prefix).
import Redis from "ioredis";

let _client = null;

function getClient() {
  if (_client) return _client;
  const url = process.env.REDIS_URL || process.env.KV_URL || process.env.UPSTASH_REDIS_URL;
  if (!url) {
    throw new Error(
      "REDIS_URL is not set. Connect a Redis database in Vercel (Storage) to this project."
    );
  }
  _client = new Redis(url, { maxRetriesPerRequest: 3 });
  _client.on("error", () => {}); // avoid crashing the function on transient errors
  return _client;
}

const ONLINE_MS = 30000; // a device is "online" if seen within 30s

// ---- Per-device command queue (FIFO: push left, agent pops right) ----
export async function pushCommand(deviceId, cmd) {
  const c = getClient();
  const key = `pc:cmd:${deviceId}`;
  await c.lpush(key, JSON.stringify(cmd));
  await c.ltrim(key, 0, 49); // keep at most 50 pending
}

export async function popCommand(deviceId) {
  const c = getClient();
  const v = await c.rpop(`pc:cmd:${deviceId}`);
  return v ? JSON.parse(v) : null;
}

// ---- Device registry (a hash: deviceId -> {name, os, ts}) ----
export async function registerDevice(deviceId, info) {
  const c = getClient();
  const data = { name: info.name || deviceId, os: info.os || "", ts: Date.now() };
  await c.hset("pc:devices", deviceId, JSON.stringify(data));
}

export async function listDevices() {
  const c = getClient();
  const all = await c.hgetall("pc:devices");
  const out = [];
  for (const [id, v] of Object.entries(all || {})) {
    try {
      const d = JSON.parse(v);
      out.push({
        id,
        name: d.name || id,
        os: d.os || "",
        ts: d.ts || 0,
        online: Date.now() - (d.ts || 0) < ONLINE_MS,
      });
    } catch {}
  }
  out.sort((a, b) => (b.ts || 0) - (a.ts || 0));
  return out;
}

export async function removeDevice(deviceId) {
  const c = getClient();
  await c.hdel("pc:devices", deviceId);
  await c.del(`pc:cmd:${deviceId}`);
}

// ---- Per-command result, so the phone can see what happened. Expires after 5 min. ----
export async function setResult(id, result) {
  const c = getClient();
  await c.set(`pc:result:${id}`, JSON.stringify(result), "EX", 300);
}

export async function getResult(id) {
  const c = getClient();
  const v = await c.get(`pc:result:${id}`);
  return v ? JSON.parse(v) : null;
}
