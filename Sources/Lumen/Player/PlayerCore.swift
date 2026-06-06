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

    /// True once the render context exists. Until then, opens are queued so
    /// mpv's vo=libmpv always has a render context when a file loads.
    private var rendererReady = false
    private var pendingURL: URL?

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
            FileHandle.standardError.write(Data("[mpv/\(prefix)] \(text)".utf8))

        case MPV_EVENT_FILE_LOADED:
            Task { @MainActor [weak self] in
                self?.fileLoaded = true
                self?.refreshEdrMode()
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
            default:
                break
            }

        default:
            break
        }
    }

    // MARK: - Actions

    func open(url: URL) {
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
            layer.enableHDR(colorSpaceName: colorSpaceName)
            mpv.setFlag("icc-profile-auto", false)
            mpv.setString("target-prim", primaries)
            mpv.setString("target-trc", "pq") // HLG is converted to PQ by mpv
            mpv.setString("target-peak", "auto")
            mpv.setFlag("screenshot-tag-colorspace", true)
            NSLog("Lumen: EDR ON (gamma=\(gamma), primaries=\(primaries), screenEDR=\(screenEDR))")
        } else {
            // SDR: restore defaults so mpv tone-maps/handles output normally.
            layer.disableHDR()
            mpv.setString("target-trc", "auto")
            mpv.setString("target-prim", "auto")
            mpv.setString("target-peak", "auto")
            mpv.setFlag("screenshot-tag-colorspace", false)
            if isHDRContent {
                NSLog("Lumen: HDR content but EDR not enabled (screenEDR=\(screenEDR))")
            }
        }
    }

    func shutdown() {
        renderer.destroy()
        mpv.terminate()
    }
}
