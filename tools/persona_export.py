import sqlite3, json
DB = "/AstrBot/data/data_v4.db"
out = "/tmp/personas_export.json"
con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True, timeout=15)
con.row_factory = sqlite3.Row
cur = con.cursor()
cur.execute("PRAGMA table_info(personas)")
cols = [r[1] for r in cur.fetchall()]
cur.execute("SELECT * FROM personas ORDER BY id")
rows = [dict(r) for r in cur.fetchall()]
cur.execute("SELECT scope, scope_id, key, value FROM preferences")
prefs = [dict(r) for r in cur.fetchall()]
cur.execute("SELECT * FROM persona_folders")
folders = [dict(r) for r in cur.fetchall()]
con.close()
payload = {"cols": cols, "personas": rows, "preferences": prefs, "folders": folders}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
print("WROTE", out, "personas=%d folders=%d prefs=%d" % (len(rows), len(folders), len(prefs)))
for r in rows:
    print("  id=%s persona_id=%r len=%d" % (r["id"], r["persona_id"], len(r["system_prompt"] or "")))
