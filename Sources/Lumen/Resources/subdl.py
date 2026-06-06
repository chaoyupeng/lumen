#!/usr/bin/env python3
"""Lumen subtitle downloader.

Downloads subtitles for a video using subliminal's KEY-FREE providers and saves
them next to the video. Prints a single JSON object to stdout; all logging goes
to stderr so stdout is always clean JSON.

Usage:
    subdl.py <video_path> <lang1> [lang2 ...]

Languages are IETF tags (en, es, pt-BR, zh-Hans, ...).

Output (stdout):
    {"results": [{"language": "en", "provider": "podnapisi", "path": "/.../x.en.srt"}],
     "error": null}
On failure `error` is a string and `results` is [].
"""
import json
import sys
import traceback

# Providers that work without any account / API key, ordered roughly by catalog
# breadth. opensubtitles (anonymous XML-RPC) + bsplayer (hash-based) cover MOVIES
# well; gestdown/tvsubtitles are TV-focused; podnapisi/napiprojekt are extras.
KEYFREE_PROVIDERS = [
    "opensubtitles",   # anonymous XML-RPC; large movie + TV catalog, hash matching
    "bsplayer",        # anonymous, hash-based; good exact-release matches
    "podnapisi",       # movies + TV
    "gestdown",        # Addic7ed proxy (TV)
    "tvsubtitles",     # TV
    "napiprojekt",     # Polish, hash-based
]


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def emit(results, error=None):
    print(json.dumps({"results": results, "error": error}))


def main():
    if len(sys.argv) < 3:
        emit([], "usage: subdl.py <video_path> <lang...>")
        return 2

    video_path = sys.argv[1]
    lang_args = sys.argv[2:]

    try:
        from babelfish import Language
        from subliminal import (
            download_best_subtitles,
            region,
            save_subtitles,
            scan_video,
        )
        from subliminal.subtitle import get_subtitle_path
    except Exception as e:  # pragma: no cover
        log(traceback.format_exc())
        emit([], f"subliminal import failed: {e}")
        return 1

    # Configure the cache region (required by subliminal; idempotent).
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
        emit([], "no valid languages")
        return 2

    try:
        video = scan_video(video_path)
    except Exception as e:
        log(traceback.format_exc())
        emit([], f"could not read video: {e}")
        return 1

    # download_best_subtitles forwards **kwargs to the ProviderPool, so
    # providers= selects exactly our key-free set. subliminal catches
    # per-provider errors internally, so one failing provider does not abort.
    try:
        found = download_best_subtitles({video}, languages, providers=KEYFREE_PROVIDERS)
        subtitles = found.get(video, [])
    except Exception as e:
        log(traceback.format_exc())
        emit([], f"subtitle search failed: {e}")
        return 1

    try:
        saved = save_subtitles(video, subtitles)
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

    log(f"downloaded {len(results)} subtitle(s)")
    emit(results, None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
