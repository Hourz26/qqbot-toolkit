#!/bin/bash
# AstrBot 数据热备份（服务器端）
# 关键点：SQLite 用 sqlite3 backup API 做一致性快照，不锁库、不停服、不破坏 WAL。
# 用法：bash backup-astrbot.sh
# 环境变量：
#   OUTDIR=/root/astrbot-backups   产出目录
#   KEEP=14                        服务器端保留份数
#   WITH_MEME_PACKS=0              1=连表情包一起备份
#   WITH_PLUGINS=0                 1=连插件源码一起备份
set -uo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
OUTDIR=${OUTDIR:-/root/astrbot-backups}
KEEP=${KEEP:-14}
WITH_MEME_PACKS=${WITH_MEME_PACKS:-0}
WITH_PLUGINS=${WITH_PLUGINS:-0}

DATA=/opt/astrbot/data
HOT=$DATA/_hotbak
STAGE=/root/_bk_stage_$STAMP
ARCHIVE=$OUTDIR/astrbot-data-$STAMP.tar.gz

mkdir -p "$OUTDIR"
rm -rf "$STAGE"
mkdir -p "$STAGE/data"

cleanup() {
  rm -rf "$STAGE"
  rm -rf "$HOT"
}
trap cleanup EXIT

# ---------- 1) SQLite 一致性热快照 ----------
echo "[1/4] hot snapshot of sqlite databases"
rm -rf "$HOT"
mkdir -p "$HOT"
docker exec astrbot python - <<'PY'
import os, sqlite3
root = '/AstrBot/data'
dst_root = os.path.join(root, '_hotbak')
ok = skip = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ('_hotbak', '__pycache__')]
    for fn in filenames:
        if not fn.endswith('.db'):
            continue
        src = os.path.join(dirpath, fn)
        rel = os.path.relpath(src, root)
        dst = os.path.join(dst_root, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        try:
            s = sqlite3.connect('file:%s?mode=ro' % src, uri=True, timeout=10)
            d = sqlite3.connect(dst)
            with d:
                s.backup(d)
            d.close()
            s.close()
            ok += 1
        except Exception as e:
            skip += 1
            print('  SKIP %s (%s)' % (rel, e))
print('  snapshot ok=%d skip=%d' % (ok, skip))
PY
if [ ! -d "$HOT" ]; then
  echo "ERROR: hot snapshot dir missing"
  exit 1
fi

# ---------- 2) 组装待打包内容 ----------
echo "[2/4] staging files"
cd "$DATA" || exit 1
for f in cmd_config.json skills.json mcp_server.json; do
  [ -f "$f" ] && cp -a "$f" "$STAGE/data/" 2>/dev/null
done
[ -d config ] && cp -a config "$STAGE/data/"
[ -d knowledge_base ] && cp -a knowledge_base "$STAGE/data/"
[ -d plugin_data ] && cp -a plugin_data "$STAGE/data/"

# plugin_data / knowledge_base 里有活库，删掉，统一用 _hotbak 里的一致性副本
find "$STAGE/data" -type f \( -name '*.db' -o -name '*.db-wal' -o -name '*.db-shm' \) -delete 2>/dev/null
find "$STAGE/data" -type f -name '*.bak*' -delete 2>/dev/null
find "$STAGE/data" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null
if [ "$WITH_MEME_PACKS" != "1" ]; then
  rm -rf "$STAGE/data/plugin_data/meme_manager/packs"
fi
if [ "$WITH_PLUGINS" = "1" ]; then
  cp -a plugins "$STAGE/data/" 2>/dev/null
  find "$STAGE/data/plugins" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null
  find "$STAGE/data/plugins" -type d -name '.git' -prune -exec rm -rf {} + 2>/dev/null
fi

# 一致性快照放在同级，保持原有相对路径
cp -a "$HOT" "$STAGE/data/_hotbak"

# ---------- 3) 打包 ----------
echo "[3/4] compressing"
tar -czf "$ARCHIVE" -C "$STAGE/data" . || { echo "ERROR: tar failed"; exit 1; }

# ---------- 4) 轮转 ----------
echo "[4/4] rotate on server (keep $KEEP)"
COUNT=$(ls -1t "$OUTDIR"/astrbot-data-*.tar.gz 2>/dev/null | wc -l)
if [ "$COUNT" -gt "$KEEP" ]; then
  ls -1t "$OUTDIR"/astrbot-data-*.tar.gz | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -f "$old"
    echo "  removed $(basename "$old")"
  done
fi

SIZE=$(stat -c %s "$ARCHIVE")
echo "RESULT:$ARCHIVE:$SIZE"
