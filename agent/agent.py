#!/usr/bin/env python3
"""
Remote PC Control - Agent
=========================
Runs on your PC, polls the Vercel server for commands, and executes them:
shutdown / restart / sleep / lock / logoff / cancel / Wake-on-LAN.

- You control only your own PC: every request is protected by a secret token
  (AGENT_TOKEN) that must match the one set in Vercel.
- Fully transparent: it only runs a fixed, known set of actions and logs each step.
- It opens no ports and accepts no inbound connections - it asks the server
  (safe behind your router).

Run:
    python agent.py
Setup: copy config.example.json to config.json and fill in the values.
"""

import json
import os
import platform
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.environ.get("RPC_CONFIG", os.path.join(HERE, "config.json"))
LOG_PATH = os.path.join(HERE, "agent.log")
OS_NAME = platform.system()  # 'Windows' | 'Linux' | 'Darwin'

ALLOWED = {"shutdown", "restart", "sleep", "lock", "logoff", "cancel", "wake"}


# --------------------------- helpers ---------------------------

def log(*a):
    """Print to screen and also append to agent.log (useful for background runs)."""
    line = time.strftime("[%Y-%m-%d %H:%M:%S] ") + " ".join(str(x) for x in a)
    try:
        print(line, flush=True)
    except Exception:
        pass
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _trim_log(max_bytes=1_000_000):
    """Trim the log file if it grows too large."""
    try:
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > max_bytes:
            with open(LOG_PATH, "r", encoding="utf-8", errors="ignore") as f:
                tail = f.readlines()[-500:]
            with open(LOG_PATH, "w", encoding="utf-8") as f:
                f.writelines(tail)
    except Exception:
        pass


def load_config():
    if not os.path.exists(CONFIG_PATH):
        log("ERROR: config.json not found. Copy config.example.json to config.json and fill it in.")
        sys.exit(1)
    with open(CONFIG_PATH, "r", encoding="utf-8-sig") as f:  # utf-8-sig tolerates a BOM
        cfg = json.load(f)
    for key in ("server_url", "agent_token"):
        if not cfg.get(key):
            log(f"ERROR: value '{key}' is missing in config.json")
            sys.exit(1)
    cfg["server_url"] = cfg["server_url"].rstrip("/")
    cfg.setdefault("poll_interval", 2)
    cfg.setdefault("heartbeat_interval", 15)
    return cfg


def http(url, method="GET", token=None, body=None, timeout=25):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["x-agent-token"] = token
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def run(cmd):
    """Run a system command. Raises on failure."""
    log("exec:", " ".join(cmd))
    subprocess.run(cmd, check=True)


# --------------------------- actions ---------------------------

def do_action(action, delay=0):
    delay = int(delay or 0)

    if OS_NAME == "Windows":
        if action == "shutdown":
            run(["shutdown", "/s", "/t", str(delay)])
        elif action == "restart":
            run(["shutdown", "/r", "/t", str(delay)])
        elif action == "logoff":
            run(["shutdown", "/l"])
        elif action == "cancel":
            run(["shutdown", "/a"])
        elif action == "lock":
            run(["rundll32.exe", "user32.dll,LockWorkStation"])
        elif action == "sleep":
            # Note: if Hibernate is enabled it may hibernate instead.
            # To disable hibernate (as admin): powercfg -h off
            run(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"])
        else:
            raise ValueError(f"unknown action: {action}")

    elif OS_NAME == "Linux":
        if action == "shutdown":
            run(["systemctl", "poweroff"])
        elif action == "restart":
            run(["systemctl", "reboot"])
        elif action == "sleep":
            run(["systemctl", "suspend"])
        elif action == "lock":
            run(["loginctl", "lock-session"])
        elif action == "logoff":
            run(["loginctl", "terminate-user", os.environ.get("USER", "")])
        elif action == "cancel":
            run(["shutdown", "-c"])
        else:
            raise ValueError(f"unknown action: {action}")

    elif OS_NAME == "Darwin":  # macOS
        if action == "shutdown":
            run(["osascript", "-e", 'tell application "System Events" to shut down'])
        elif action == "restart":
            run(["osascript", "-e", 'tell application "System Events" to restart'])
        elif action == "sleep":
            run(["pmset", "sleepnow"])
        elif action == "lock":
            run(["pmset", "displaysleepnow"])
        elif action == "logoff":
            run(["osascript", "-e", 'tell application "System Events" to log out'])
        elif action == "cancel":
            raise ValueError("cancel is not supported on macOS")
        else:
            raise ValueError(f"unknown action: {action}")

    else:
        raise RuntimeError(f"unsupported OS: {OS_NAME}")


def do_wake(cfg):
    from wol import wake  # wol.py sits next to this file
    mac = cfg.get("wol_mac")
    bcast = cfg.get("wol_broadcast", "255.255.255.255")
    wake(mac, bcast)


# --------------------------- main loop ---------------------------

def main():
    cfg = load_config()
    base = cfg["server_url"]
    token = cfg["agent_token"]
    poll_interval = float(cfg["poll_interval"])
    hb_interval = float(cfg["heartbeat_interval"])
    host = socket.gethostname()

    _trim_log()
    log(f"starting | server={base} | host={host} | os={OS_NAME}")
    log("waiting for commands... (stop with Ctrl+C)")

    last_hb = 0.0
    while True:
        now = time.time()
        try:
            # heartbeat (shows 'online' on your phone)
            if now - last_hb >= hb_interval:
                http(f"{base}/api/heartbeat", "POST", token, {"hostname": host, "os": OS_NAME})
                last_hb = now

            # ask for the next command
            data = http(f"{base}/api/poll", "GET", token)
            cmd = data.get("command")
            if cmd:
                action = cmd.get("action")
                cid = cmd.get("id")
                delay = cmd.get("delay", 0)
                log(f"received command: {action} (id={cid})")

                if action not in ALLOWED:
                    http(f"{base}/api/ack", "POST", token,
                         {"id": cid, "status": "error", "message": f"rejected unknown action: {action}"})
                    continue

                # tell the phone it was received right away (before the PC powers off)
                try:
                    http(f"{base}/api/ack", "POST", token,
                         {"id": cid, "status": "accepted", "message": "executing"})
                except Exception:
                    pass

                try:
                    if action == "wake":
                        do_wake(cfg)
                        msg = "magic packet sent (WoL)"
                    else:
                        do_action(action, delay)
                        msg = "ok"
                    # report success (may not arrive if the PC powers off immediately - that's fine)
                    try:
                        http(f"{base}/api/ack", "POST", token,
                             {"id": cid, "status": "done", "message": msg})
                    except Exception:
                        pass
                    log("executed:", action, "-", msg)
                except Exception as e:
                    log("failed to execute", action, ":", e)
                    try:
                        http(f"{base}/api/ack", "POST", token,
                             {"id": cid, "status": "error", "message": str(e)})
                    except Exception:
                        pass

        except urllib.error.HTTPError as e:
            if e.code == 401:
                log("ERROR 401: agent_token does not match the one set in Vercel. Check the config.")
                time.sleep(5)
            else:
                log("HTTP error:", e.code, e.reason)
        except urllib.error.URLError as e:
            log("network error (will retry):", e.reason)
            time.sleep(3)
        except KeyboardInterrupt:
            log("stopping.")
            break
        except Exception as e:
            log("unexpected error:", e)

        time.sleep(poll_interval)


if __name__ == "__main__":
    main()
