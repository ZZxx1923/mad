// Shared helper for talking to Vercel KV / Upstash Redis over its REST API.
// Files under api/_lib are NOT turned into routes by Vercel (underscore prefix).

const URL = process.env.KV_REST_API_URL;
const TOKEN = process.env.KV_REST_API_TOKEN;

async function kv(command) {
  if (!URL || !TOKEN) {
    throw new Error(
      "KV is not configured. Create a Vercel KV / Upstash store and it will set KV_REST_API_URL and KV_REST_API_TOKEN automatically."
    );
  }
  const res = await fetch(URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
  });
  if (!res.ok) {
    throw new Error(`KV error ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  return data.result;
}

// ---- Command queue (newest pushed on the left, agent pops from the right = FIFO) ----
export async function pushCommand(cmd) {
  await kv(["LPUSH", "pc:commands", JSON.stringify(cmd)]);
  await kv(["LTRIM", "pc:commands", "0", "49"]); // keep at most 50 pending
}

export async function popCommand() {
  const v = await kv(["RPOP", "pc:commands"]);
  return v ? JSON.parse(v) : null;
}

// ---- Heartbeat: the agent proves it's alive. Auto-expires after 60s. ----
export async function setHeartbeat(info) {
  await kv(["SET", "pc:heartbeat", JSON.stringify(info), "EX", "60"]);
}

export async function getHeartbeat() {
  const v = await kv(["GET", "pc:heartbeat"]);
  return v ? JSON.parse(v) : null;
}

// ---- Per-command result, so the phone can see what happened. Expires after 5 min. ----
export async function setResult(id, result) {
  await kv(["SET", `pc:result:${id}`, JSON.stringify(result), "EX", "300"]);
}

export async function getResult(id) {
  const v = await kv(["GET", `pc:result:${id}`]);
  return v ? JSON.parse(v) : null;
}
