"""Patch the installed biliVideo plugin so Bilibili downloads bypass yt-dlp.

The HTML page www.bilibili.com/video/<BV> answers HTTP 412 to every
browser-like UA from this datacenter IP, which kills yt-dlp before it can
reach the JSON APIs. The APIs themselves work fine with UA "Mozilla/5.0",
so we route bilibili URLs through ``bili_native`` and leave yt-dlp for
YouTube / Douyin / everything else.

Idempotent: re-running only re-copies bili_native.py and skips patched anchors.
"""

from __future__ import annotations

import ast
import shutil
import sys
from pathlib import Path

PLUGIN = Path("/AstrBot/data/plugins/astrbot_plugin_bilivideo")
DL = PLUGIN / "bilivideo" / "downloader"
TARGET = DL / "ytdlp_downloader.py"
NATIVE_SRC = Path("/tmp/bili_native.py")
NATIVE_DST = DL / "bili_native.py"

MARK = "        # --- bili-native override ---"

ANCHOR_INIT = """    def update_cookies(self, cookies: Mapping[str, str] | None) -> None:
        if not cookies:"""

REPL_INIT = """    def update_cookies(self, cookies: Mapping[str, str] | None) -> None:
        # keep the raw cookie mapping for the native Bilibili path
        self._cookies_map = {str(k): str(v) for k, v in (cookies or {}).items() if v}
        if not cookies:"""

ANCHOR_AUDIO = '''        target = Path(output_dir) if output_dir else self._data_dir
        target.mkdir(parents=True, exist_ok=True)

        opts = {'''

REPL_AUDIO = '''        target = Path(output_dir) if output_dir else self._data_dir
        target.mkdir(parents=True, exist_ok=True)

''' + MARK + '''
        if detect_platform(video_url) == "bilibili":
            try:
                from .bili_native import _Cancelled as _NativeCancelled
                from .bili_native import download_audio as _native_download_audio

                return _native_download_audio(
                    video_url,
                    data_dir=target,
                    cookies=getattr(self, "_cookies_map", None),
                    quality=quality,
                    cancel_event=cancel_event,
                )
            except _NativeCancelled:
                raise
            except Exception as exc:
                logger.warning(f"native bilibili audio failed, falling back to yt-dlp: {exc}")
        # --- end bili-native override ---

        opts = {'''

ANCHOR_SUB = """        lang_list = list(langs) if langs else list(DEFAULT_SUBTITLE_LANGS)"""

REPL_SUB = """        lang_list = list(langs) if langs else list(DEFAULT_SUBTITLE_LANGS)

""" + MARK + """
        if detect_platform(video_url) == "bilibili":
            try:
                from .bili_native import download_subtitles as _native_subtitles

                return _native_subtitles(
                    video_url,
                    cookies=getattr(self, "_cookies_map", None),
                    langs=tuple(lang_list),
                )
            except Exception as exc:
                logger.warning(f"native bilibili subtitles failed: {exc}")
                return None
        # --- end bili-native override ---"""

PATCHES = (
    ("update_cookies", ANCHOR_INIT, REPL_INIT, "self._cookies_map = {"),
    ("download_audio", ANCHOR_AUDIO, REPL_AUDIO, "native bilibili audio failed"),
    ("download_subtitles", ANCHOR_SUB, REPL_SUB, "native bilibili subtitles failed"),
)


def main() -> int:
    if not TARGET.exists():
        print(f"FAIL target missing: {TARGET}")
        return 2
    if not NATIVE_SRC.exists():
        print(f"FAIL native source missing: {NATIVE_SRC}")
        return 2

    shutil.copyfile(NATIVE_SRC, NATIVE_DST)
    print(f"copied native module -> {NATIVE_DST} ({NATIVE_DST.stat().st_size} bytes)")

    src = TARGET.read_text(encoding="utf-8")

    for name, anchor, repl, already in PATCHES:
        if already in src:
            print(f"skip {name}: already patched")
            continue
        if anchor not in src:
            print(f"FAIL anchor not found for {name}")
            return 3
        src = src.replace(anchor, repl, 1)
        print(f"patched {name}")

    TARGET.write_text(src, encoding="utf-8")
    ast.parse(src)
    print("ast.parse OK")
    print(f"final size: {TARGET.stat().st_size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
