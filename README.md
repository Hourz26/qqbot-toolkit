# QQ 机器人（SnowLuma + AstrBot）运维工具箱

一套围绕 **AstrBot + QQ 协议端** 的实战配置、补丁与运维脚本合集。原始需求是给一个私人 QQ 小号接上大模型人格，过程中踩了大量坑（协议端登录、容器路径、插件权限、配置双写、定时备份、上游网关风控），这里把可复用的部分沉淀下来。

> ⚠️ 仓库内所有密钥都已替换成 `REPLACE_WITH_*` 占位符，**没有一个可用凭据**。照抄前请自己填。

## 目录

```
docs/            交接文档 + 停机记录（架构、端口、坑位清单）
persona/         人格卡（QQ 群友版小鲸鱼），可直接贴进 AstrBot 人格配置
scripts/         一键启动、配置校验、环境修复脚本
  backup/        云端 AstrBot 数据热备份 + 拉取 + 还原（SQLite 一致性快照）
patches/bilivideo/  B 站视频理解插件的原生下载补丁（绕开 yt-dlp 的 B 站 412）
config-templates/  脱敏后的 AstrBot 配置样例（含各插件配置）
tools/           诊断 / 迁移 / 打补丁的 Python 小工具
```

## 架构（两种部署形态）

**A. 本机 Windows（SnowLuma 注入式）**

```
QQ 客户端(小号) → SnowLuma(:5099 面板 / :3000 HTTP / :3001 WS)
                → ws://127.0.0.1:6199/ws → AstrBot(:6185 面板) → DeepSeek API
```

**B. 云服务器 Linux（NapCat headless）**

```
QQ(无头, xvfb) → NapCat(:6099 WebUI, OneBot11 反向 WS)
               → ws://127.0.0.1:6199/ws → AstrBot(Docker :6185) → DeepSeek API
```

关键实测结论：

- **SnowLuma 依赖注入 `QQ.exe`，Linux 上用不了**，云上必须换 NapCat / Lagrange / LLBot。
- 容器里 AstrBot 的数据目录是 **`/AstrBot/data`**，不是 `/astrbot/data`。`docker-compose.yml` 挂错点会导致配置和插件完全没持久化。
- `ws_reverse_host` 必须是 `0.0.0.0` 而不是 `127.0.0.1`，否则 Docker 的 `docker-proxy` 从 `172.x.0.1` 进来会被 loopback-only 的 Hypercorn 拒绝，表现为 NapCat 每 3 秒 `socket hang up`。
- 容器里的 AstrBot 把 `/AstrBot/data/...` 路径交给宿主机上的 NapCat 读文件时会 `ENOENT`，宿主机执行 `ln -s /opt/astrbot /AstrBot` 即可。
- 2 GB 内存跑 AstrBot + NapCat 需要 2–4 GB swap，否则 OOM 会静默杀掉协议端。

## scripts/

| 文件 | 作用 |
|---|---|
| `start-qqbot.ps1` | Windows 一键启动：PM2 起 AstrBot / SnowLuma → 等端口 → 按 UIN 匹配 QQ 进程并注入 hook → 校验 OneBot 与 WS |
| `check-astrbot-config.py` | 用 AstrBot 自己的 `CONFIG_METADATA_2` 校验 `cmd_config.json`，精确打印面板会报的那几条错误 |
| `cleanup-junk.ps1` | 清理 `%TEMP%` / CrashDumps / WinGet 缓存，输出释放量 |
| `fix-workbuddy-hosts.ps1` | 上游域名被网络拦截时，pin 到官方 fallback IP（需管理员） |
| `backup/backup-astrbot-remote.sh` | 服务端热备份：`sqlite3` backup API 快照全部 `.db` → 打包 → 打印 `RESULT:<path>:<bytes>` |
| `backup/backup-pull.ps1` | 本机拉取：触发远端 → scp → 校验字节数 / tar 可读 / 关键文件存在 → 轮转 |
| `backup/restore.ps1` | 还原（支持 `-WhatIf`），先快照当前状态再覆盖，失败可回滚 |

备份脚本的核心是**不停容器也能拿到一致快照**：

```python
s = sqlite3.connect('file:%s?mode=ro' % src, uri=True, timeout=10)
d = sqlite3.connect(dst)
with d:
    s.backup(d)
```

打包前把 stage 里所有 `*.db` / `*.db-wal` / `*.db-shm` 删掉，只保留 `_hotbak/` 下的一致副本，所以归档里不会出现半截 WAL。

## patches/bilivideo/

B 站插件（`astrbot_plugin_biliVideo`）用 yt-dlp 下音频/字幕时经常被 412 风控。这里改成走 B 站原生接口：

- `bili_native.py` — 原生取播放地址 + 拉字幕 + 取音频
- `patch_bilivideo.py` — 对 `bilivideo/downloader/ytdlp_downloader.py` 打三处补丁（可重复执行）
- `ytdlp_downloader.py` — 打完补丁的成品（14568 → 16077 字节），可直接对照
- `restore-deps.sh` — 容器重建后补装依赖（pip 装进容器层，`--force-recreate` 会丢）

用法：

```bash
docker cp bili_native.py astrbot:/tmp/bili_native.py
docker cp patch_bilivideo.py astrbot:/tmp/patch_bilivideo.py
docker exec astrbot python /tmp/patch_bilivideo.py
cd /opt/astrbot && docker compose restart astrbot
```

## config-templates/

`cmd_config.template.json` 和 6 个插件配置，都是**脱敏后的真实运行配置**。重点看这几处：

- `platform[].ws_reverse_host` = `0.0.0.0`（见上面的坑）
- `admins_id` 里必须放**真实 QQ 号**，默认的 `["astrbot"]` 不是 QQ 号，导致所有人都是 member
- `provider_settings.computer_use_local_permissions` 里 member 的 `allow_execution:false` 需要 `bwrap` 沙箱，容器里没有就永远拒绝；给 admin 的 `filesystem_scope:"host"` 才不需要沙箱
- 插件的同一组开关常常存在「顶层扁平键 + 分组」两份，**分组是权威**，只改顶层会被启动迁移覆盖回去

## tools/

| 文件 | 作用 |
|---|---|
| `patch_wb_channel.py` | 给 dsh-workbuddy-connect 打「渠道身份改写」补丁（见下一个仓库） |
| `verify_wb_channel.py` | 该补丁的行为测试（6 条用例） |
| `set_bili_prefs.py` | 通过 HTTP API 改 bili-scroll 偏好，并同步清掉 `cordis.patch.yml` 里的覆盖块 |
| `fix_meme_proactive.py` / `diag_meme_proactive.py` | 表情包不发送 / 主动消息不触发的定位与修复（含 intensity preset 覆盖配置的坑） |
| `persona_export.py` / `persona_import.py` | 人格在 AstrBot 实例之间搬运（含 UMO 前缀改写） |
| `gh_issues.py` / `gh_pr.py` / `llbot_release.py` | GitHub / LLBot 发布资产查询小工具 |

## 踩过的坑（精选）

1. **PowerShell 5.1 读 UTF-8 无 BOM 的含中文脚本会按 GBK 解码**，直接语法报错。`.ps1` 带中文必须存 UTF-8 **带** BOM；`.sh` 发给 Linux 必须 LF + 无 BOM（否则 `tail: invalid number of lines: '60\r'`）。
2. **别用 `pm2 jlist` 喂 `ConvertFrom-Json`**：输出的 JSON 里 `username` / `USERNAME` 重复键会让 PowerShell 直接报错，判定实例健康直接用端口探测。
3. **AstrBot 插件备份目录不能放在 `plugins/` 下**，否则会被当成插件扫描并再次触发依赖冲突。
4. **插件的 `.bak` 目录 / `__pycache__` 要排除**，meme 表情包 300 MB 起，别塞进备份。
5. **`companions.json` 这类插件数据文件必须是 UTF-8 无 BOM**，写成 `utf-8-sig` 会让插件加载时 `JSONDecodeError` 然后整个插件被卸载；而 AstrBot 自己的 `cmd_config.json` 是**带** BOM 的。

## License

MIT，见 `LICENSE`。人格卡里的梗和语气属于随手写的玩笑，随便改。
