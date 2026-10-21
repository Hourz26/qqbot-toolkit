# AstrBot 数据备份说明

## 一句话

云端每天 04:00 自动热备份（不停服）→ 拉到本机 `D:\qqbot-backups\` → 本地保留 30 份，服务器保留 14 份。

## 文件在哪

| 位置 | 内容 |
|---|---|
| `C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\backup-pull.ps1` | 本机拉取脚本 |
| `C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\restore.ps1` | 还原脚本 |
| `C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\run-backup.cmd` | 计划任务包装器 |
| 服务器 `/root/backup-astrbot.sh` | 服务器端热备份脚本 |
| 服务器 `/root/restore-deps.sh` | 容器依赖恢复（还原后自动跑） |
| **本机 `D:\qqbot-backups\`** | 备份归档落地目录 |
| `D:\qqbot-backups\logs\scheduler.log` | 计划任务日志 |
| 服务器 `/root/astrbot-backups/` | 服务器侧副本 |

## 备份里有什么

✅ **包含**
- `cmd_config.json`（平台/模型/面板配置）
- `config/*.json`（5 个插件的配置，含对话分段、陪伴、主动消息）
- `_hotbak/`（**10 个 SQLite 库的一致性快照**）
  - `data_v4.db` — 会话历史、人格、偏好、UMO 别名
  - `plugin_data/astrbot_plugin_memory_companion/memory_companion.db` — **长期记忆**
  - `plugin_data/astrbot_plugin_memory_companion/req041_scoped.db`
  - `plugin_data/astrbot_plugin_private_companion/req041_relationship.db` — 关系/好感
  - `plugin_data/astrbot_plugin_private_companion/req041_migration_control.db`
  - `plugin_data/astrbot_plugin_private_companion/req041_migration_outbox.db`
  - `plugin_data/astrbot_plugin_private_companion/persona_profiles/default.db`
  - `plugin_data/astrbot_plugin_self_learning/messages.db`
  - `knowledge_base/kb.db`
  - 以及 `req041_backups/` 里的历史快照
- `plugin_data/astrbot_plugin_private_companion/companions.json` — **陪伴关系、人设、投递路由**
- `plugin_data/` 其余内容（图片缓存、表情库、时间线等）

❌ **不包含**（可用环境变量开启）
- `meme_manager/packs/` 表情包 306MB → `WITH_MEME_PACKS=1`
- `plugins/` 插件源码 70MB → `WITH_PLUGINS=1`

不含这些是因为它们可从市场重新安装，且会在 2G 内存机器上拖慢备份。**关键的记忆、关系、配置都在。**

## 关键技术点：不停服热备份

直接 `cp` 一个正在写的 SQLite 会得到损坏文件。这里用 **SQLite 官方 backup API**：

```python
s = sqlite3.connect('file:%s?mode=ro' % src, uri=True, timeout=10)
d = sqlite3.connect(dst)
with d:
    s.backup(d)
```

跑在容器内（`docker exec -i astrbot python -`），一次性快照全部 10 个库，**不锁库、不停服、不动 WAL**。实测 `snapshot ok=10 skip=0`。

归档内的 db 一律走 `_hotbak/` 里的一致性副本，原始位置上的活跃 db 在打包前被删除，所以不会出现「半截 WAL」问题。

## 常用命令

```powershell
# 手动备份一次（立即）
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\backup-pull.ps1"

# 查看最近备份
Get-ChildItem 'D:\qqbot-backups' -Filter '*.tar.gz' | Sort-Object LastWriteTime -Descending

# 看某份备份里有什么
tar -tzf 'D:\qqbot-backups\astrbot-data-XXXX.tar.gz'

# 计划任务状态
Get-ScheduledTaskInfo -TaskName 'AstrBot-DailyBackup'

# 改保留份数（默认 30）
powershell ... -File backup-pull.ps1 -Keep 60
```

## 还原

```powershell
# 先空跑看流程
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Hourz26\Desktop\Deepseek\qqbot-backup\restore.ps1" `
  -Archive "D:\qqbot-backups\astrbot-data-20261020-142648.tar.gz" -WhatIf

# 真还原
powershell -NoProfile -ExecutionPolicy Bypass -File "...\restore.ps1" `
  -Archive "D:\qqbot-backups\astrbot-data-20261020-142648.tar.gz"
```

还原做的事：上传 → 服务器端把当前 `data` 存到 `/root/restore-backup-<ts>` → 停容器 → 解包覆盖 → `_hotbak/*.db` 回原路径 → 启容器 → 补依赖 → 健康检查。**全程有回滚点。**

回滚：

```bash
ssh aliyun 'cd /opt/astrbot && docker compose stop astrbot && rm -rf data && cp -a /root/restore-backup-<ts> data && docker compose start astrbot'
```

## 前提条件

- 本机 `ssh aliyun` 免密可用（`C:\Users\Hourz26\.ssh\config`，密钥 `id_ed25519_dsh`）
- 服务器 `/root/backup-astrbot.sh` 存在
- 计划任务 `AstrBot-DailyBackup` 的「主机名\用户名」需能登录才跑得起来；如果换了 Windows 账户或改了密码，任务会失败，需要重建

## 已知限制

- **只在机器开着的时候跑**。计划任务配了 `StartWhenAvailable`，所以错过了（关机/睡眠）会在开机补跑一次。
- 备份不含 `plugins/` 与表情包，还原后需重新装包。
- `pip install` 的 4 个额外依赖（`chinese-calendar`、`lunarcalendar`、`boto3`、`tqdm`）装在容器层，**还原脚本会自动重装**；但如果是你自己 `docker compose up --force-recreate`，需要手动跑 `bash /root/restore-deps.sh`。
