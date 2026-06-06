import AppKit
import Cmpv
import SwiftUI
import UniformTypeIdentifiers

/// App-facing playback model. Owns the single mpv instance and the renderer,
/// configures mpv with defaults preserved (so output matches raw mpv), and
/// translates mpv events into observable SwiftUI state.
@MainActor
final class PlayerCore: ObservableObject {
    let mpv = MPVClient()
    let renderer = MPVRenderer()

    @Published var isPaused = false
    @Published var fileLoaded = false
    @Published var currentTitle = ""
    /// True while EDR/HDR output is active (HDR content on an EDR display).
    @Published var isHDRActive = false
    /// Short human-readable color description, e.g. "HDR10 · PQ · BT.2020".
    @Published var colorInfo = ""

    @Published var timePos: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 100
    @Published var subtitleTracks: [Track] = []
    @Published var audioTracks: [Track] = []

    @Published var isDownloadingSubs = false
    @Published var isSyncing = false
    @Published var subStatus: String?

    /// Lumen downloads English subtitles only.
    let subtitleLanguages = ["en"]

    private(set) var currentPath: String?

    /// True once the render context exists. Until then, opens are queued so
    /// mpv's vo=libmpv always has a render context when a file loads.
    private var rendererReady = false
    private var pendingURL: URL?

    weak var videoView: VideoNSView?

    init() {
        configure()
    }

    private func configure() {
        // Pre-init options. We deliberately do NOT touch any HDR/color/tone-map
        // option — mpv's defaults ARE the behavior we want to match. vo=libmpv
        // is set pre-init so the render-API path is guaranteed regardless of a
        // user's mpv.conf.
        mpv.setOptionString("config", "no")            // deterministic defaults for now
        mpv.setOptionString("vo", "libmpv")
        mpv.setOptionString("input-default-bindings", "yes")
        mpv.setOptionString("input-vo-keyboard", "no") // we feed keys ourselves (M2)
        mpv.setOptionString("osc", "no")
        mpv.setOptionString("osd-bar", "no")
        mpv.setOptionString("terminal", "no")
        mpv.setOptionString("keep-open", "yes")
        mpv.setOptionString("hwdec", "auto-safe")
        // Uniform subtitle appearance: force mpv's own style over embedded ASS
        // styling, so external (.srt) and embedded subs look identical.
        mpv.setOptionString("sub-ass-override", "force")

        mpv.requestLogMessages("warn")
        mpv.setWakeupCallback()

        // Observe before initialize.
        mpv.observe("pause", MPV_FORMAT_FLAG)
        mpv.observe("dwidth", MPV_FORMAT_INT64)
        mpv.observe("dheight", MPV_FORMAT_INT64)
        mpv.observe("media-title", MPV_FORMAT_STRING)
        // HDR detection inputs — drive EDR refresh when they change.
        mpv.observe("video-params/gamma", MPV_FORMAT_STRING)
        mpv.observe("video-params/primaries", MPV_FORMAT_STRING)
        // Playback + track state for the controls UI.
        mpv.observe("time-pos", MPV_FORMAT_DOUBLE)
        mpv.observe("duration", MPV_FORMAT_DOUBLE)
        mpv.observe("volume", MPV_FORMAT_DOUBLE)
        mpv.observe("track-list", MPV_FORMAT_NONE)
        mpv.observe("sid", MPV_FORMAT_NONE)
        mpv.observe("aid", MPV_FORMAT_NONE)

        mpv.onEvent = { [weak self] ev in self?.handle(event: ev) }

        renderer.onReady = { [weak self] in
            guard let self else { return }
            self.rendererReady = true
            if let url = self.pendingURL {
                self.pendingURL = nil
                self.mpv.command(["loadfile", url.path])
            }
        }

        if !mpv.initialize() {
            NSLog("Lumen: mpv_initialize failed")
        }

        // Open a file passed on the command line (also used for smoke tests).
        if let path = CommandLine.arguments.dropFirst().first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) {
            open(url: URL(fileURLWithPath: path))
        }
    }

    // Runs on the mpv event queue (background). Copy out what we need, then hop
    // to the main actor for state updates.
    nonisolated private func handle(event ev: UnsafePointer<mpv_event>) {
        switch ev.pointee.event_id {
        case MPV_EVENT_LOG_MESSAGE:
            let m = ev.pointee.data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            let prefix = String(cString: m.prefix)
            let text = String(cString: m.text)
            // Known-benign one-time GL state check on the CAOpenGLLayer path;
            // playback/HDR are unaffected. Don't spam it to the console.
            if text.contains("INVALID_FRAMEBUFFER_OPERATION") { return }
            FileHandle.standardError.write(Data("[mpv/\(prefix)] \(text)".utf8))

        case MPV_EVENT_FILE_LOADED:
            Task { @MainActor [weak self] in
                self?.fileLoaded = true
                self?.refreshEdrMode()
                self?.updateWindowSize()
                self?.reloadTracks()
                self?.autoConfigureSubtitles()
            }

        case MPV_EVENT_PROPERTY_CHANGE:
            let p = ev.pointee.data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: p.name)
            switch name {
            case "pause":
                if p.format == MPV_FORMAT_FLAG, let d = p.data {
                    let paused = d.assumingMemoryBound(to: Int32.self).pointee != 0
                    Task { @MainActor [weak self] in self?.isPaused = paused }
                }
            case "media-title":
                if p.format == MPV_FORMAT_STRING, let d = p.data {
                    let cstr = d.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
                    if let cstr = cstr {
                        let title = String(cString: cstr)
                        Task { @MainActor [weak self] in self?.currentTitle = title }
                    }
                }
            case "video-params/gamma", "video-params/primaries":
                Task { @MainActor [weak self] in self?.refreshEdrMode() }
            case "dwidth", "dheight":
                Task { @MainActor [weak self] in self?.updateWindowSize() }
            case "time-pos":
                if p.format == MPV_FORMAT_DOUBLE, let d = p.data {
                    let v = d.assumingMemoryBound(to: Double.self).pointee
                    Task { @MainActor [weak self] in self?.timePos = v }
                }
            case "duration":
                if p.format == MPV_FORMAT_DOUBLE, let d = p.data {
                    let v = d.assumingMemoryBound(to: Double.self).pointee
                    Task { @MainActor [weak self] in self?.duration = v }
                }
            case "volume":
                if p.format == MPV_FORMAT_DOUBLE, let d = p.data {
                    let v = d.assumingMemoryBound(to: Double.self).pointee
                    Task { @MainActor [weak self] in self?.volume = v }
                }
            case "track-list", "sid", "aid":
                Task { @MainActor [weak self] in self?.reloadTracks() }
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Actions

    func open(url: URL) {
        currentPath = url.path
        subStatus = nil
        if rendererReady {
            mpv.command(["loadfile", url.path])
        } else {
            pendingURL = url
        }
    }

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .video, .audiovisualContent]
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func togglePause() {
        mpv.setFlag("pause", !(mpv.getFlag("pause") ?? false))
    }

    func attachVideoView(_ view: VideoNSView) {
        videoView = view
    }

    /// Forward a translated key to mpv; its default bindings handle the action.
    func sendKey(_ key: String) {
        mpv.command(["keypress", key])
    }

    /// Resize the window to the video's native display size. dwidth/dheight are
    /// in pixels (already aspect-corrected by mpv).
    func updateWindowSize() {
        guard let dw = mpv.getInt("dwidth"), let dh = mpv.getInt("dheight"),
              dw > 0, dh > 0 else { return }
        videoView?.resizeWindow(toVideoWidth: Int(dw), height: Int(dh))
    }

    // MARK: - Playback controls

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        mpv.command(["seek", String(fraction * duration), "absolute"])
    }

    func setVolume(_ value: Double) {
        mpv.setDouble("volume", value)
    }

    func adjustVolume(by delta: Double) {
        mpv.command(["add", "volume", String(delta)])
    }

    // MARK: - Subtitles

    /// Re-read the track list and selection state from mpv.
    func reloadTracks() {
        let count = mpv.getInt("track-list/count") ?? 0
        var subs: [Track] = []
        var audios: [Track] = []
        for i in 0..<count {
            let type = mpv.getString("track-list/\(i)/type") ?? ""
            let id = mpv.getInt("track-list/\(i)/id") ?? 0
            let title = mpv.getString("track-list/\(i)/title")
            let lang = mpv.getString("track-list/\(i)/lang")
            let external = mpv.getFlag("track-list/\(i)/external") ?? false
            let externalFilename = mpv.getString("track-list/\(i)/external-filename")
            let selected = mpv.getFlag("track-list/\(i)/selected") ?? false
            let track = Track(id: id, type: type, title: title, lang: lang,
                              external: external, externalFilename: externalFilename,
                              selected: selected)
            switch type {
            case "sub": subs.append(track)
            case "audio": audios.append(track)
            default: break
            }
        }
        subtitleTracks = subs
        audioTracks = audios
    }

    func selectAudio(id: Int64) {
        mpv.setInt("aid", id)
        reloadTracks()
    }

    func selectSubtitle(id: Int64?) {
        if let id {
            mpv.setInt("sid", id)
        } else {
            mpv.setString("sid", "no")
        }
        reloadTracks()
    }

    func addSubtitleFile(_ url: URL) {
        mpv.command(["sub-add", url.path, "select"])
        reloadTracks()
    }

    /// Whether an audio-based sync tool (alass/ffsubsync) is available.
    var subtitleSyncAvailable: Bool { SyncService.isAvailable }

    /// Automatically sync the selected external subtitle against the audio and
    /// reload the corrected file. Silently does nothing if no sync tool is
    /// available or the active subtitle isn't an external file (e.g. embedded).
    func syncCurrentSubtitle() {
        guard SyncService.isAvailable,
              let video = currentPath,
              let sub = subtitleTracks.first(where: { $0.selected }),
              let subPath = sub.externalFilename else { return }
        let oldSid = sub.id
        isSyncing = true
        subStatus = "Syncing subtitle to audio…"
        Task { @MainActor in
            defer { isSyncing = false }
            do {
                let synced = try await SyncService.sync(videoPath: video, subtitlePath: subPath)
                mpv.command(["sub-remove", String(oldSid)])
                mpv.command(["sub-add", synced, "select"])
                reloadTracks()
                subStatus = "Subtitle synced to audio."
            } catch {
                // Keep the downloaded subtitle as-is; don't nag.
                subStatus = nil
            }
        }
    }

    func openSubtitleFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let subTypes = ["srt", "ass", "ssa", "vtt", "sub", "idx"]
            .compactMap { UTType(filenameExtension: $0) }
        if !subTypes.isEmpty { panel.allowedContentTypes = subTypes }
        if panel.runModal() == .OK, let url = panel.url {
            addSubtitleFile(url)
        }
    }

    /// Whether the subtitle download feature is usable (subliminal installed).
    var subtitleDownloadAvailable: Bool { SubtitleService.isAvailable }

    private var autoSubtitlesEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoSubtitles") as? Bool ?? true
    }

    /// On file load: prefer the video's embedded subtitles (selecting one in the
    /// user's language if possible); if there are none, auto-download them.
    func autoConfigureSubtitles() {
        guard autoSubtitlesEnabled else { return }
        if !subtitleTracks.isEmpty {
            // Embedded subtitles exist — ensure one is active, preferring a
            // track whose language matches the user's first choices.
            if !subtitleTracks.contains(where: { $0.selected }) {
                let preferred = subtitleLanguages.map { String($0.prefix(2)).lowercased() }
                let match = subtitleTracks.first { track in
                    guard let lang = track.lang?.lowercased() else { return false }
                    return preferred.contains { lang.hasPrefix($0) }
                }
                selectSubtitle(id: (match ?? subtitleTracks[0]).id)
            }
        } else if subtitleDownloadAvailable, !isDownloadingSubs {
            // No embedded subtitles — fetch them automatically.
            downloadSubtitles(languages: subtitleLanguages)
        }
    }

    /// Download subtitles for the current file in the given IETF languages,
    /// then load them into mpv (first selected, rest added but inactive).
    func downloadSubtitles(languages: [String]) {
        guard let path = currentPath else {
            subStatus = "No video open."
            return
        }
        guard !languages.isEmpty else {
            subStatus = "Pick at least one language."
            return
        }
        isDownloadingSubs = true
        subStatus = "Searching…"
        Task { @MainActor in
            defer { isDownloadingSubs = false }
            do {
                let outcome = try await SubtitleService.download(videoPath: path, languages: languages)
                if !outcome.results.isEmpty {
                    for (index, result) in outcome.results.enumerated() {
                        guard let p = result.path else { continue }
                        mpv.command(["sub-add", p, index == 0 ? "select" : "auto"])
                    }
                    reloadTracks()
                    let n = outcome.results.count
                    subStatus = "Added \(n) subtitle\(n == 1 ? "" : "s")."
                    // Auto-sync the loaded subtitle to the audio (if a tool exists).
                    syncCurrentSubtitle()
                } else if outcome.listed > 0 {
                    // Found candidates but couldn't download them — almost always
                    // the OpenSubtitles.com login requirement.
                    subStatus = "Found \(outcome.listed), but download needs a free "
                        + "OpenSubtitles.com account. Add it in Settings (⌘,)."
                } else {
                    subStatus = "No subtitles found."
                }
            } catch let error as SubtitleError {
                subStatus = error.errorDescription
            } catch {
                subStatus = error.localizedDescription
            }
        }
    }

    /// Enable or disable EDR/HDR output based on the current video's transfer
    /// and primaries, the display's EDR capability, and mirror mpv's output
    /// encoding to the layer's colorspace. Mirrors IINA's requestEdrMode logic.
    /// Must run on the main thread.
    func refreshEdrMode() {
        guard let layer = renderer.layer else { return }
        let gamma = mpv.getString("video-params/gamma") ?? ""
        let primaries = mpv.getString("video-params/primaries") ?? ""
        let isHDRContent = (gamma == "pq" || gamma == "hlg")
        let screenEDR = layer.hostScreen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0

        var colorSpaceName: CFString?
        if isHDRContent && screenEDR > 1.0 {
            switch primaries {
            case "display-p3": colorSpaceName = CGColorSpace.displayP3_PQ
            case "bt.2020": colorSpaceName = CGColorSpace.itur_2100_PQ
            default: colorSpaceName = nil
            }
        }

        if let colorSpaceName {
            // HDR on: tell the layer it's PQ EDR, and have mpv output PQ to match.
            let wasActive = isHDRActive
            layer.enableHDR(colorSpaceName: colorSpaceName)
            mpv.setFlag("icc-profile-auto", false)
            mpv.setString("target-prim", primaries)
            mpv.setString("target-trc", "pq") // HLG is converted to PQ by mpv
            mpv.setString("target-peak", "auto")
            mpv.setFlag("screenshot-tag-colorspace", true)
            isHDRActive = true
            let label = (gamma == "hlg") ? "HLG" : "HDR10"
            colorInfo = "\(label) · PQ · \(primaries.uppercased())"
            if !wasActive {
                NSLog("Lumen: EDR ON (gamma=\(gamma), primaries=\(primaries), screenEDR=\(screenEDR))")
            }
        } else {
            // SDR: restore defaults so mpv tone-maps/handles output normally.
            layer.disableHDR()
            mpv.setString("target-trc", "auto")
            mpv.setString("target-prim", "auto")
            mpv.setString("target-peak", "auto")
            mpv.setFlag("screenshot-tag-colorspace", false)
            isHDRActive = false
            if isHDRContent {
                colorInfo = "HDR content · EDR unavailable (display SDR)"
                NSLog("Lumen: HDR content but EDR not enabled (screenEDR=\(screenEDR))")
            } else {
                colorInfo = primaries.isEmpty ? "" : "SDR · \(primaries.uppercased())"
            }
        }
    }

    func shutdown() {
        renderer.destroy()
        mpv.terminate()
    }
}
