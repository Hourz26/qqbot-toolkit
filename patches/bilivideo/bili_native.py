"""Native Bilibili downloader.

Bypasses the ``www.bilibili.com`` HTML page (which returns HTTP 412 to any
browser-like User-Agent coming from datacenter IPs) by talking to the JSON
APIs directly:

  * ``/x/web-interface/view``  -> bvid -> aid + cid
  * ``/x/player/playurl``      -> DASH audio stream URLs
  * ``/x/player/v2``           -> platform subtitles (needs SESSDATA)

Only ``Mozilla/5.0`` is sent as UA because that is the one value Bilibili's
WAF accepts from this host; every richer UA gets 412.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import threading
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from ..core.constants import QUALITY_TO_KBPS
from ..core.logging import get_logger
from ..core.types import AudioDownloadResult, TranscriptResult, TranscriptSegment

logger = get_logger("BiliVideo/Native")

API = "https://api.bilibili.com"
UA = "Mozilla/5.0"
REFERER = "https://www.bilibili.com/"
TIMEOUT = 20


class _Cancelled(Exception):
    pass


def _headers(cookies: dict[str, str] | None) -> dict[str, str]:
    h = {"User-Agent": UA, "Referer": REFERER}
    if cookies:
        h["Cookie"] = "; ".join(f"{k}={v}" for k, v in cookies.items() if v)
    return h


def _get_json(url: str, cookies: dict[str, str] | None, params: dict[str, Any] | None = None):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers=_headers(cookies))
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _extract_bvid(url: str) -> str | None:
    import re

    m = re.search(r"BV[0-9A-Za-z]{10}", url or "")
    return m.group(0) if m else None


def _ffmpeg() -> str | None:
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def fetch_video_meta(bvid: str, cookies: dict[str, str] | None) -> tuple[int, int, dict]:
    """Return (aid, cid, raw_view_data)."""

    payload = _get_json(f"{API}/x/web-interface/view", cookies, {"bvid": bvid})
    if payload.get("code") != 0:
        raise RuntimeError(f"view API code={payload.get('code')} msg={payload.get('message')}")
    data = payload["data"]
    pages = data.get("pages") or []
    if not pages:
        raise RuntimeError("view API returned no pages")
    return int(data["aid"]), int(pages[0]["cid"]), data


def pick_audio_url(bvid: str, cid: int, cookies: dict[str, str] | None) -> tuple[str, str]:
    payload = _get_json(
        f"{API}/x/player/playurl",
        cookies,
        {"bvid": bvid, "cid": cid, "fnval": 4048, "fnver": 0, "fourk": 1},
    )
    if payload.get("code") != 0:
        raise RuntimeError(f"playurl code={payload.get('code')} msg={payload.get('message')}")
    dash = (payload.get("data") or {}).get("dash") or {}
    audios = dash.get("audio") or []
    if audios:
        # lowest bandwidth keeps the 2 GB VPS light while ASR quality holds up
        best = min(audios, key=lambda a: a.get("bandwidth") or 0)
        return best.get("baseUrl") or best.get("base_url"), "dash"
    durl = (payload.get("data") or {}).get("durl") or []
    if durl:
        return durl[0]["url"], "durl"
    raise RuntimeError("playurl returned neither dash audio nor durl")


def download_audio(
    video_url: str,
    *,
    data_dir: Path,
    cookies: dict[str, str] | None,
    quality: str = "fast",
    cancel_event: threading.Event | None = None,
) -> AudioDownloadResult:
    bvid = _extract_bvid(video_url)
    if not bvid:
        raise RuntimeError("not a bilibili BV url")
    aid, cid, view = fetch_video_meta(bvid, cookies)
    url, kind = pick_audio_url(bvid, cid, cookies)
    logger.info(f"native audio: bvid={bvid} aid={aid} cid={cid} kind={kind}")

    data_dir.mkdir(parents=True, exist_ok=True)
    raw_path = data_dir / f"{bvid}.m4s"
    req = urllib.request.Request(url, headers={**_headers(cookies), "Referer": REFERER})
    with urllib.request.urlopen(req, timeout=60) as resp, raw_path.open("wb") as fp:
        while True:
            if cancel_event is not None and cancel_event.is_set():
                fp.close()
                raw_path.unlink(missing_ok=True)
                raise _Cancelled()
            chunk = resp.read(262144)
            if not chunk:
                break
            fp.write(chunk)

    mp3_path = data_dir / f"{bvid}.mp3"
    kbps = QUALITY_TO_KBPS.get(quality, "64")
    ff = _ffmpeg()
    if not ff:
        # no ffmpeg: hand the raw m4s to BCut as-is, it probes with ffmpeg-free
        # codecs by extension, so rename to mp3 anyway is wrong -> keep m4s
        logger.warning("ffmpeg missing; BCut gets the raw m4s stream")
        mp3_path = raw_path
    else:
        proc = subprocess.run(
            [
                ff, "-y", "-loglevel", "error", "-i", str(raw_path),
                "-vn", "-acodec", "libmp3lame", "-ar", "16000", "-ac", "1",
                "-b:a", f"{kbps}k", str(mp3_path),
            ],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {proc.stderr[-400:]}")
        raw_path.unlink(missing_ok=True)

    return AudioDownloadResult(
        file_path=str(mp3_path),
        title=str(view.get("title", "")),
        duration=float(view.get("duration", 0) or 0),
        cover_url=view.get("pic"),
        platform="bilibili",
        video_id=bvid,
        raw_info=dict(view),
    )


def download_subtitles(
    video_url: str,
    *,
    cookies: dict[str, str] | None,
    langs: tuple[str, ...] | None = None,
) -> TranscriptResult | None:
    """Platform (CC / AI) subtitles. Requires SESSDATA, else returns None."""

    bvid = _extract_bvid(video_url)
    if not bvid:
        return None
    if not (cookies or {}).get("SESSDATA"):
        logger.info(f"{bvid}: no SESSDATA -> skip platform subtitles, use ASR")
        return None

    aid, cid, _view = fetch_video_meta(bvid, cookies)
    payload = _get_json(f"{API}/x/player/v2", cookies, {"aid": aid, "cid": cid})
    if payload.get("code") != 0:
        logger.warning(f"player/v2 code={payload.get('code')} msg={payload.get('message')}")
        return None
    subs = ((payload.get("data") or {}).get("subtitle") or {}).get("subtitles") or []
    if not subs:
        logger.info(f"{bvid}: no platform subtitles available")
        return None

    wanted = langs or ("zh-Hans", "zh", "zh-CN", "ai-zh", "en", "en-US")
    chosen = None
    for want in wanted:
        for s in subs:
            if s.get("lan") == want:
                chosen = s
                break
        if chosen:
            break
    if chosen is None:
        chosen = subs[0]

    sub_url = chosen.get("subtitle_url") or ""
    if sub_url.startswith("//"):
        sub_url = "https:" + sub_url
    if not sub_url:
        return None
    body = _get_json(sub_url, cookies)
    segments: list[TranscriptSegment] = []
    for entry in body.get("body") or []:
        text = (entry.get("content") or "").strip()
        if not text:
            continue
        segments.append(
            TranscriptSegment(
                start=float(entry.get("from", 0) or 0),
                end=float(entry.get("to", 0) or 0),
                text=text,
            )
        )
    if not segments:
        return None
    logger.info(f"native subtitle hit: {chosen.get('lan')} segments={len(segments)}")
    return TranscriptResult(
        language=chosen.get("lan"),
        full_text=" ".join(s.text for s in segments),
        segments=tuple(segments),
        raw={"source": "bilibili_subtitle", "format": "json", "lan": chosen.get("lan")},
    )
