// Shared Redis helper. Works with any Redis connection string (REDIS_URL),
// as provided by Vercel Storage (Upstash / Official Redis).
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

// ---- Command queue (newest pushed on the left, agent pops from the right = FIFO) ----
export async function pushCommand(cmd) {
  const c = getClient();
  await c.lpush("pc:commands", JSON.stringify(cmd));
  await c.ltrim("pc:commands", 0, 49); // keep at most 50 pending
}

export async function popCommand() {
  const c = getClient();
  const v = await c.rpop("pc:commands");
  return v ? JSON.parse(v) : null;
}

// ---- Heartbeat: the agent proves it's alive. Auto-expires after 60s. ----
export async function setHeartbeat(info) {
  const c = getClient();
  await c.set("pc:heartbeat", JSON.stringify(info), "EX", 60);
}

export async function getHeartbeat() {
  const c = getClient();
  const v = await c.get("pc:heartbeat");
  return v ? JSON.parse(v) : null;
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
