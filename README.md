# Lumen

A native macOS video player that **embeds [libmpv](https://mpv.io) in-process** to match raw mpv's HDR / 4K / 10-bit / audio quality — with a modern **Liquid Glass** interface, **automatic subtitle download**, and **audio-based auto-sync**.

Built from scratch in Swift + SwiftUI/AppKit. One `mpv_handle`, rendered into a `CAOpenGLLayer` with app-managed EDR for correct HDR. No Electron, no subprocess mpv.

## Features

- 🎬 **mpv-quality playback** — real HDR10/HLG EDR output (orange **HDR** badge when active), 10-bit, 4K, hardware-decoded. mpv's defaults preserved, so it looks like mpv.
- 💬 **Automatic subtitles** — on open, uses the video's embedded subtitles, or downloads English subtitles from the internet (OpenSubtitles.com) and loads them.
- 🪄 **Auto-sync** — downloaded subtitles are automatically synced to the audio (bundled `alass` + `ffmpeg` — nothing to install).
- 🔊 **Audio + subtitle track switching**, drag-and-drop, keyboard control (Space, ←/→ seek, ↑/↓ volume, `f` fullscreen, and all of mpv's bindings).
- ✨ **Liquid Glass UI** — floating glass controls, immersive window, auto-hiding bar.
- ⬆️ **In-app update check** (via GitHub Releases).

## Install

1. Download the latest **`Lumen-x.y.z.dmg`** from [Releases](https://github.com/chaoyupeng/lumen/releases).
2. Open it and drag **Lumen** into **Applications**.
3. **First launch:** because the app isn't notarized with an Apple Developer ID yet, macOS will block it once. Either:
   - **Right-click Lumen → Open → Open**, or
   - run `xattr -dr com.apple.quarantine /Applications/Lumen.app` in Terminal.

   After that it opens normally.

**Requirements:** Apple Silicon, **macOS 26+**. Everything (libmpv, ffmpeg, alass) is bundled — no Homebrew needed.

> To download subtitles you'll sign in to a **free** [OpenSubtitles.com](https://www.opensubtitles.com/newuser) account under **Settings (⌘,)** — the old no-account API was shut down in Jan 2026.

## Build from source

Requires the Xcode Command Line Tools + Homebrew (no full Xcode needed):

```sh
brew install mpv subliminal alass   # libmpv + subtitle tooling
swift run                           # run (debug)
make dmg                            # build the signed .app + DMG in dist/
```

## License

GPLv3 — Lumen links and bundles libmpv (which is GPL). See [LICENSE](LICENSE).

---

🤖 Built with [Claude Code](https://claude.com/claude-code).
