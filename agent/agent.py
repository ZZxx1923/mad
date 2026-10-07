#!/usr/bin/env python3
"""
Remote PC Control — Agent
=========================
يعمل هذا البرنامج على جهازك (البيسي)، يسأل سيرفر Vercel باستمرار عن الأوامر،
وينفّذها: إيقاف / إعادة تشغيل / سكون / قفل / تسجيل خروج / إلغاء / Wake-on-LAN.

- تحكّم بجهازك أنت فقط: كل طلب محمي برمز سري (AGENT_TOKEN) يطابق المضبوط في Vercel.
- شفّاف تماماً: ينفّذ فقط قائمة أوامر ثابتة ومعروفة، ويطبع كل خطوة في السجل.
- لا يفتح أي منفذ ولا يستقبل اتصالات واردة — هو من يسأل السيرفر (آمن خلف الراوتر).

التشغيل:
    python agent.py
الإعداد: انسخ config.example.json إلى config.json واملأ القيم.
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
OS_NAME = platform.system()  # 'Windows' | 'Linux' | 'Darwin'

ALLOWED = {"shutdown", "restart", "sleep", "lock", "logoff", "cancel", "wake"}


# --------------------------- helpers ---------------------------

def log(*a):
    print(time.strftime("[%H:%M:%S]"), *a, flush=True)


def load_config():
    if not os.path.exists(CONFIG_PATH):
        log("ERROR: config.json غير موجود. انسخ config.example.json إلى config.json واملأه.")
        sys.exit(1)
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    for key in ("server_url", "agent_token"):
        if not cfg.get(key):
            log(f"ERROR: القيمة '{key}' ناقصة في config.json")
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
    """نفّذ أمر نظام. يرفع استثناء عند الفشل."""
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
            # ملاحظة: إذا كان الإسبات (Hibernate) مفعّلاً قد ينام إسباتاً.
            # لإيقاف الإسبات: powercfg -h off  (كمسؤول)
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
            raise ValueError("cancel غير مدعوم على macOS")
        else:
            raise ValueError(f"unknown action: {action}")

    else:
        raise RuntimeError(f"نظام تشغيل غير مدعوم: {OS_NAME}")


def do_wake(cfg):
    from wol import wake  # ملف wol.py بجانب هذا الملف
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

    log(f"بدء التشغيل | server={base} | host={host} | os={OS_NAME}")
    log("في انتظار الأوامر… (أوقِف بـ Ctrl+C)")

    last_hb = 0.0
    while True:
        now = time.time()
        try:
            # نبضة الحياة (تُظهر 'متصل' في الجوال)
            if now - last_hb >= hb_interval:
                http(f"{base}/api/heartbeat", "POST", token, {"hostname": host, "os": OS_NAME})
                last_hb = now

            # اسأل عن الأمر التالي
            data = http(f"{base}/api/poll", "GET", token)
            cmd = data.get("command")
            if cmd:
                action = cmd.get("action")
                cid = cmd.get("id")
                delay = cmd.get("delay", 0)
                log(f"استلمت أمراً: {action} (id={cid})")

                if action not in ALLOWED:
                    http(f"{base}/api/ack", "POST", token,
                         {"id": cid, "status": "error", "message": f"رُفض أمر غير معروف: {action}"})
                    continue

                # أبلغ الجوال بالاستلام فوراً (قبل ما ينطفئ الجهاز)
                try:
                    http(f"{base}/api/ack", "POST", token,
                         {"id": cid, "status": "accepted", "message": "جارِ التنفيذ"})
                except Exception:
                    pass

                try:
                    if action == "wake":
                        do_wake(cfg)
                        msg = "تم إرسال إشارة التشغيل (WoL)"
                    else:
                        do_action(action, delay)
                        msg = "تم"
                    # أبلغ بالنجاح (قد لا يصل إن انطفأ الجهاز فوراً — وهذا طبيعي)
                    try:
                        http(f"{base}/api/ack", "POST", token,
                             {"id": cid, "status": "done", "message": msg})
                    except Exception:
                        pass
                    log("نُفّذ:", action, "—", msg)
                except Exception as e:
                    log("فشل تنفيذ", action, ":", e)
                    try:
                        http(f"{base}/api/ack", "POST", token,
                             {"id": cid, "status": "error", "message": str(e)})
                    except Exception:
                        pass

        except urllib.error.HTTPError as e:
            if e.code == 401:
                log("ERROR 401: الرمز السري (agent_token) لا يطابق المضبوط في Vercel. راجع الإعداد.")
                time.sleep(5)
            else:
                log("HTTP error:", e.code, e.reason)
        except urllib.error.URLError as e:
            log("خطأ شبكة (سيُعاد المحاولة):", e.reason)
            time.sleep(3)
        except KeyboardInterrupt:
            log("إيقاف البرنامج.")
            break
        except Exception as e:
            log("خطأ غير متوقع:", e)

        time.sleep(poll_interval)


if __name__ == "__main__":
    main()
