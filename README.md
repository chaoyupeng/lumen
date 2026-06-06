# Lumen

A native macOS video player that **embeds [libmpv](https://mpv.io) in-process** to match raw mpv's HDR / 4K / 10-bit / audio quality, and adds the four things mpv itself lacks:

1. **Key-free internet subtitle download** with a multi-language picker (no API key required).
2. **Reference-free, audio-based subtitle auto-sync** — fixes delay and framerate drift against the video's own audio.
3. **In-app "Check for Updates"** (via GitHub Releases).
4. **Clean, self-contained distribution** — a double-clickable `.app` with libmpv bundled inside.

Built from scratch in Swift + SwiftUI/AppKit. No Electron, no subprocess mpv — one `mpv_handle`, rendered into a `CAOpenGLLayer` (IINA-style render API), with app-managed EDR for correct HDR.

> **Status:** early development. Milestone 1 (embedded libmpv playback + HDR) in progress.

## Why

[IINA](https://iina.io) is the established macOS mpv frontend, but its HDR/4K output can diverge from raw mpv (version lag + defaults). Lumen's core principle: **preserve mpv's defaults** so output matches `mpv` itself, and bundle a pinned libmpv so HDR is reproducible and immune to `brew upgrade`.

## Build (Command Line Tools only — no Xcode required)

Requires the Xcode Command Line Tools, Homebrew, and `mpv` (for libmpv + headers):

```sh
brew install mpv
swift build      # or: make build
swift run        # or: make run
```

Optional runtime tools (detected at runtime; the app prompts to install if missing):

```sh
brew install subliminal   # key-free subtitle download
brew install alass        # audio-based subtitle auto-sync
```

## Platform

- Apple Silicon, macOS. The shipped minimum-OS floor is dictated by the bundled
  libmpv's build target (currently **macOS 26.0** for the Homebrew build).

## License

GPLv3 — Lumen links and bundles libmpv (which is GPL). See [LICENSE](LICENSE).

---

🤖 Architecture designed with [Claude Code](https://claude.com/claude-code).
