#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, os, sqlite3, glob

DATA = "/opt/astrbot/data"
CFG = os.path.join(DATA, "config")


def load(p):
    try:
        with open(p, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception as e:
        return {"__error__": str(e)}


def dig(d, *path, default=None):
    cur = d
    for k in path:
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return default
    return cur


print("=" * 70)
print("MEME MANAGER")
print("=" * 70)
mm = load(os.path.join(CFG, "meme_manager_config.json"))
if "__error__" in mm:
    print("config error:", mm["__error__"])
else:
    emo = dig(mm, "generation", "emotion", default={})
    print("enabled(app):", dig(mm, "enabled"), " plugin_enabled:", dig(mm, "plugin_enabled"))
    print("generation.emotion.probability :", emo.get("probability"))
    print("generation.emotion.max_memes_per_message:", emo.get("max_memes_per_message"))
    print("generation.emotion.llm.enabled:", dig(emo, "llm", "enabled"))
    print("generation.emotion.cooldown:", emo.get("cooldown_seconds"), emo.get("cooldown"))
    print("prompt.quantity_guidance_enabled:", dig(mm, "prompt", "quantity_guidance_enabled"))
    print("top-level keys:", sorted(mm.keys())[:40])

pd = os.path.join(DATA, "plugin_data", "meme_manager")
print("\nplugin_data/meme_manager exists:", os.path.isdir(pd))
if os.path.isdir(pd):
    for root, dirs, files in os.walk(pd):
        depth = root[len(pd):].count(os.sep)
        if depth > 2:
            dirs[:] = []
            continue
        n = len(files)
        sz = sum(os.path.getsize(os.path.join(root, f)) for f in files if os.path.isfile(os.path.join(root, f)))
        if depth <= 1:
            print(f"  {root[len(pd):] or '/'}: {n} files, {sz/1024/1024:.1f} MB")
    packs = os.path.join(pd, "packs")
    if os.path.isdir(packs):
        for p in sorted(os.listdir(packs)):
            fp = os.path.join(packs, p)
            if os.path.isdir(fp):
                cnt = sum(len(fs) for _, _, fs in os.walk(fp))
                print(f"   pack {p}: {cnt} files")

print("\n" + "=" * 70)
print("PROACTIVE (private_companion)")
print("=" * 70)
pc = load(os.path.join(CFG, "astrbot_plugin_private_companion_config.json"))
if "__error__" in pc:
    print("config error:", pc["__error__"])
else:
    bc = pc.get("basic_config", {}) or {}
    for k in ("enable_proactive_only_mode", "default_proactive_enabled", "default_proactive_daily_limit",
              "idle_minutes", "generation_disabled", "enable_standalone_webui", "quiet_hours"):
        print(f"  top.{k} =", pc.get(k), " | basic_config:", bc.get(k))
    for grp in ("proactive_reach_config", "private_followup_config", "daily_creative_config"):
        g = pc.get(grp, {}) or {}
        keys = [k for k in g if "proactiv" in k or "idle" in k or "interval" in k]
        if keys:
            print(f"  [{grp}] " + ", ".join(f"{k}={g[k]}" for k in keys))

cj = os.path.join(DATA, "plugin_data", "astrbot_plugin_private_companion", "companions.json")
if os.path.exists(cj):
    cp = load(cj)
    users = cp.get("users", {}) or {}
    print("\n  companions.json users:", list(users.keys()))
    for uid, u in users.items():
        print(f"  --- user {uid} ---")
        for k in ("relationship_role", "manual_enabled", "auto_enabled",
                  "proactive_private_enabled", "proactive_daily_limit", "proactive_idle_minutes",
                  "proactive_min_interval_minutes", "proactive_sent_count", "sent_today",
                  "last_proactive_at", "next_proactive_at", "planned_proactive_reason",
                  "last_proactive_skip_reason", "last_proactive_hesitation_note",
                  "proactive_boundary_note"):
            if k in u:
                print(f"    {k} = {u[k]}")
        print("    proactive_audit_log len =", len(u.get("proactive_audit_log") or []))
        rt = u.get("proactive_runtime")
        print("    proactive_runtime =", json.dumps(rt, ensure_ascii=False) if rt else None)
else:
    print("  companions.json MISSING")

print("\n" + "=" * 70)
print("PROACTIVE CHAT (proactive_chat)")
print("=" * 70)
pcc = load(os.path.join(CFG, "astrbot_plugin_proactive_chat_config.json"))
if "__error__" in pcc:
    print("config error:", pcc["__error__"])
else:
    fs = pcc.get("friend_settings", {}) or {}
    print("  session_list:", fs.get("session_list"))
    print("  auto_trigger:", json.dumps(fs.get("auto_trigger_settings", {}), ensure_ascii=False))
    print("  schedule:", json.dumps(fs.get("schedule_settings", {}), ensure_ascii=False))
    print("  group_settings.enable:", dig(pcc, "group_settings", "enable"))

print("\n" + "=" * 70)
print("PLUGIN ENABLE STATE (db preferences)")
print("=" * 70)
db = os.path.join(DATA, "data_v4.db")
try:
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    for row in con.execute("select scope, scope_id, key, value from preferences order by key"):
        print("  ", row[0], "/", row[1], "/", row[2], "=", str(row[3])[:300])
    con.close()
except Exception as e:
    print("  db error:", e)

print("\n" + "=" * 70)
print("PLUGIN DIRS")
print("=" * 70)
pdir = os.path.join(DATA, "plugins")
if os.path.isdir(pdir):
    for d in sorted(os.listdir(pdir)):
        fp = os.path.join(pdir, d)
        if os.path.isdir(fp):
            print("  ", d)
