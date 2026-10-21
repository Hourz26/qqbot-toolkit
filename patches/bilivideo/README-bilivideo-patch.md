# B站原生 API 补丁（绕过 412 风控）

## 为什么要打

Tencent/阿里云机房 IP 访问 `https://www.bilibili.com/video/BVxxxx` 时，B 站 WAF 对所有浏览器 UA 一律返回 **HTTP 412**（连 `buvid3` 真指纹都过不去）。
biliVideo 插件默认走 yt-dlp，第一步就是抓这个网页 → 必然失败，字幕和音频都拿不到。

但 **JSON API 完全正常**：`api.bilibili.com/x/web-interface/view`、`/x/player/playurl` 用 `User-Agent: Mozilla/5.0` 就返回 200。

## 补丁做了什么

| 文件 | 作用 |
|---|---|
| `bili_native.py` | 原生 B 站下载器。`view` 取 aid/cid → `playurl` 取最低带宽 DASH 音轨 → ffmpeg 转 16k 单声道 mp3；字幕走 `player/v2`（需 SESSDATA，没有就返回 None 让流水线回落 ASR） |
| `patch_bilivideo.py` | 对插件里的 `ytdlp_downloader.py` 打三处幂等补丁：缓存原始 cookie 到 `_cookies_map`、`download_audio()` 和 `download_subtitles()` 遇到 bilibili 域名先走原生、失败再回落 yt-dlp |

非 B 站链接（YouTube / 抖音 / 小红书等）完全不受影响，仍走 yt-dlp。

## 实测结果（服务器上）

```
[BiliVideo/Native] BV1GJ411x7h7: no SESSDATA -> skip platform subtitles, use ASR
[BiliVideo/Pipeline] no platform subtitle, fall back to ASR
[BiliVideo/Native] native audio: bvid=BV1GJ411x7h7 aid=80433022 cid=137649199 kind=dash
PIPELINE OK in 5.0s
lang: zh segments: 60
audio: /tmp/_bvtest/BV1GJ411x7h7.mp3 (850281 bytes)
```

5 秒完成「元信息 → DASH 音频 0.4s → ffmpeg 转码 → 必剪 ASR 60 段」。

## 服务器上的部署位置

```
/root/astrbot-patches/
├── bili_native.py
├── patch_bilivideo.py
├── apply-bili-native.sh      # 重打补丁
└── README.txt
```

## 什么时候需要重跑

插件升级会把 `ytdlp_downloader.py` 覆盖回原版 → 补丁失效。此时跑：

```bash
bash /root/astrbot-patches/apply-bili-native.sh
cd /opt/astrbot && docker compose restart astrbot
```

脚本是幂等的，已经打过的锚点会 skip。

**容器重建（`docker compose up --force-recreate`）之后**还要先跑 `bash /root/restore-deps.sh`
补 pip 依赖（`markdown` / `imgkit` / `segno` / `imageio-ffmpeg` 等装在容器层，重建即丢）。

## 已知限制

- 没有 SESSDATA 时**拿不到平台字幕**（B 站不给未登录用户看 AI 字幕），只能走 ASR。要字幕就发 `/B站登录` 扫码。
- 必剪 ASR 依赖 B 站云端，视频太长、音频太小众时可能超时（`general.processing_timeout` 当前 600 秒）。
- 只处理 `BV` 号；`av` 号和番剧 `ep` 号没做映射。
