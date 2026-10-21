import sqlite3, json, shutil, os, datetime

DB = r"D:\Apps\astrbot\data\data_v4.db"
SRC = r"C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\personas_export.json"

stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
bak = DB + ".bak-before-personasync-" + stamp
shutil.copy2(DB, bak)
for ext in ("-wal", "-shm"):
    p = DB + ext
    if os.path.exists(p):
        shutil.copy2(p, bak + ext)
print("BACKUP:", bak)

with open(SRC, encoding="utf-8") as f:
    data = json.load(f)

cols = data["cols"]
personas = data["personas"]

con = sqlite3.connect(DB, timeout=20)
cur = con.cursor()
cur.execute("PRAGMA table_info(personas)")
local_cols = [r[1] for r in cur.fetchall()]
print("local cols:", local_cols)
missing = [c for c in cols if c not in local_cols]
print("cols missing locally:", missing)

cur.execute("SELECT id, persona_id FROM personas")
before = cur.fetchall()
print("BEFORE:", before)

added, updated, skipped = [], [], []
with con:
    for p in personas:
        pid = p["persona_id"]
        cur.execute("SELECT id FROM personas WHERE persona_id = ?", (pid,))
        row = cur.fetchone()
        vals = {c: p.get(c) for c in cols if c in local_cols}
        if row:
            # update prompt content only if different
            cur.execute("SELECT system_prompt FROM personas WHERE persona_id = ?", (pid,))
            cur_prompt = cur.fetchone()[0]
            if (cur_prompt or "") != (p.get("system_prompt") or ""):
                sets = ", ".join("%s = ?" % c for c in vals if c not in ("id", "persona_id"))
                params = [vals[c] for c in vals if c not in ("id", "persona_id")]
                params.append(pid)
                cur.execute("UPDATE personas SET %s WHERE persona_id = ?" % sets, params)
                updated.append(pid)
            else:
                skipped.append(pid)
        else:
            keys = list(vals.keys())
            cur.execute(
                "INSERT INTO personas (%s) VALUES (%s)" % (", ".join(keys), ", ".join("?" * len(keys))),
                [vals[k] for k in keys],
            )
            added.append(pid)

cur.execute("SELECT id, persona_id, length(system_prompt) FROM personas ORDER BY id")
after = cur.fetchall()
print("AFTER:", after)
con.close()
print("added:", added)
print("updated:", updated)
print("skipped(identical):", skipped)
print("integrity:", end=" ")
c2 = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
print(c2.execute("PRAGMA integrity_check").fetchone()[0])
c2.close()
