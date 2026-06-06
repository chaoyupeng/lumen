#!/usr/bin/env python3
"""Lumen subtitle downloader.

Downloads subtitles for a video using subliminal and saves them next to the
video. Prints a single JSON object to stdout; all logging goes to stderr so
stdout is always clean JSON.

Usage:
    subdl.py <video_path> <lang1> [lang2 ...]

Languages are IETF tags (en, es, pt-BR, zh-Hans, ...).

Optional OpenSubtitles.com credentials via environment (for reliable downloads
against your own free quota): OS_USERNAME, OS_PASSWORD, OS_APIKEY.

Output (stdout):
    {"results": [{"language": "en", "provider": "opensubtitlescom",
                  "path": "/.../x.en.srt"}],
     "listed": 12, "error": null}
`listed` is how many candidate subtitles were found across providers; if that is
> 0 but `results` is empty, the search worked but downloads were blocked (e.g.
rate limit) — adding an account helps. On hard failure `error` is a string.
"""
import json
import os
import sys
import traceback

# Providers, best-first. opensubtitlescom uses subliminal's built-in API key
# when no credentials are supplied (works without an account, shared quota).
# The old opensubtitles.org XML-RPC provider was shut down on 2026-01-29 and is
# intentionally omitted.
PROVIDERS = [
    "opensubtitlescom",  # OpenSubtitles.com REST; movies + TV, hash matching
    "podnapisi",         # movies + TV (flaky)
    "gestdown",          # Addic7ed proxy (TV)
    "tvsubtitles",       # TV
    "bsplayer",          # hash-based
    "napiprojekt",       # Polish, hash-based
]


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def emit(results, listed=0, error=None):
    print(json.dumps({"results": results, "listed": listed, "error": error}))


def main():
    if len(sys.argv) < 3:
        emit([], error="usage: subdl.py <video_path> <lang...>")
        return 2

    video_path = sys.argv[1]
    lang_args = sys.argv[2:]

    try:
        from babelfish import Language
        from subliminal import region, save_subtitles, scan_video
        from subliminal.core import ProviderPool
        from subliminal.subtitle import get_subtitle_path
    except Exception as e:  # pragma: no cover
        log(traceback.format_exc())
        emit([], error=f"subliminal import failed: {e}")
        return 1

    try:
        region.configure("dogpile.cache.memory")
    except Exception as e:
        log(f"region.configure: {e} (likely already configured)")

    languages = set()
    for code in lang_args:
        try:
            languages.add(Language.fromietf(code))
        except Exception as e:
            log(f"skipping invalid language '{code}': {e}")
    if not languages:
        emit([], error="no valid languages")
        return 2

    try:
        video = scan_video(video_path)
    except Exception as e:
        log(traceback.format_exc())
        emit([], error=f"could not read video: {e}")
        return 1

    # Optional OpenSubtitles.com credentials -> personal download quota.
    osc_config = {}
    for env_key, cfg_key in (("OS_USERNAME", "username"),
                             ("OS_PASSWORD", "password"),
                             ("OS_APIKEY", "apikey")):
        value = os.environ.get(env_key)
        if value:
            osc_config[cfg_key] = value
    provider_configs = {"opensubtitlescom": osc_config} if osc_config else {}
    log(f"opensubtitles.com account: {'yes' if osc_config.get('username') else 'anonymous'}")

    listed = 0
    best = []
    try:
        with ProviderPool(providers=PROVIDERS, provider_configs=provider_configs) as pool:
            candidates = pool.list_subtitles(video, languages)
            listed = len(candidates)
            log(f"found {listed} candidate subtitle(s) across providers")
            best = pool.download_best_subtitles(candidates, video, languages, min_score=0)
    except Exception as e:
        log(traceback.format_exc())
        emit([], listed=listed, error=f"subtitle search failed: {e}")
        return 1

    try:
        saved = save_subtitles(video, best)
    except Exception as e:
        log(traceback.format_exc())
        saved = []

    results = []
    for sub in saved:
        try:
            path = get_subtitle_path(video.name, sub.language)
        except Exception:
            path = None
        results.append({
            "language": str(sub.language),
            "provider": getattr(sub, "provider_name", None),
            "path": path,
        })

    log(f"downloaded {len(results)} subtitle(s) (from {listed} candidates)")
    emit(results, listed=listed, error=None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
