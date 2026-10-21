#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json, os, shutil, time

DATA = "/AstrBot/data"
CFG = os.path.join(DATA, "config")
STAMP = time.strftime("%Y%m%d-%H%M%S")


def load(p):
    with open(p, encoding="utf-8-sig") as f:
        return json.load(f)


def save(p, obj):
    with open(p, "w", encoding="utf-8-sig", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


# ---------- 1. inspect meme categories ----------
pd = os.path.join(DATA, "plugin_data", "meme_manager", "packs", "official-001")
md = os.path.join(pd, "memes_data.json")
print("=== memes_data.json (categories) ===")
try:
    data = load(md)
    if isinstance(data, dict):
        keys = list(data.keys())
        print("top keys:", keys[:20])
        cats = data.get("categories") or data.get("data") or {}
        if isinstance(cats, dict):
            for k, v in list(cats.items())[:40]:
                n = len(v) if hasattr(v, "__len__") else "?"
                print(f"   {k}  ({n})")
        elif isinstance(cats, list):
            print("list len", len(cats), "first:", json.dumps(cats[0], ensure_ascii=False)[:300])
    else:
        print("type", type(data), "len", len(data))
except Exception as e:
    print("ERR", e)

# ---------- 2. fix meme config ----------
mp = os.path.join(CFG, "meme_manager_config.json")
mm = load(mp)
shutil.copy2(mp, mp + ".bak-before-memefix-" + STAMP)
emo = mm.setdefault("generation", {}).setdefault("emotion", {})
before = {
    "llm.enabled": emo.get("llm", {}).get("enabled"),
    "probability": emo.get("probability"),
    "quantity_guidance_enabled": mm["generation"].get("prompt", {}).get("quantity_guidance_enabled"),
    "max_memes": emo.get("max_memes_per_message"),
}
emo.setdefault("llm", {})["enabled"] = True
emo["llm"]["context_turns"] = 4
emo["emotion_provider_id"] = ""
emo["probability"] = 100
emo["max_memes_per_message"] = 1
mm["generation"].setdefault("prompt", {})["quantity_guidance_enabled"] = True
save(mp, mm)
after = {
    "llm.enabled": emo["llm"]["enabled"],
    "probability": emo["probability"],
    "quantity_guidance_enabled": mm["generation"]["prompt"]["quantity_guidance_enabled"],
    "max_memes": emo["max_memes_per_message"],
}
print("\n=== meme_manager: before -> after ===")
print(" before:", before)
print(" after :", after)

# ---------- 3. fix private_companion flat defaults ----------
pp = os.path.join(CFG, "astrbot_plugin_private_companion_config.json")
pc = load(pp)
shutil.copy2(pp, pp + ".bak-before-flatsync-" + STAMP)
print("\n=== private_companion flat defaults ===")
print(" before: enabled=", pc.get("default_proactive_enabled"),
      " daily_limit=", pc.get("default_proactive_daily_limit"))
pc["default_proactive_enabled"] = True
pc["default_proactive_daily_limit"] = 6
save(pp, pc)
print(" after : enabled=", pc.get("default_proactive_enabled"),
      " daily_limit=", pc.get("default_proactive_daily_limit"))
print("\nDONE")
