import AppKit
import SwiftUI

/// The AppKit view backing the video surface. Uses ViewLayer as its backing
/// layer, is first responder for keyboard input (forwarded to mpv's default
/// bindings), and resizes its window to the video's native size.
final class VideoNSView: NSView {
    private let viewLayer: ViewLayer

    /// Forwards a translated mpv key name (e.g. "SPACE", "RIGHT", "Shift+UP").
    var keyHandler: ((String) -> Void)?
    /// Adjusts volume by a delta (for the ↑/↓ keys we handle ourselves).
    var volumeHandler: ((Double) -> Void)?

    init(renderer: MPVRenderer, mpv: OpaquePointer?) {
        viewLayer = ViewLayer(renderer: renderer)
        viewLayer.mpvHandle = mpv
        super.init(frame: .zero)
        viewLayer.hostView = self
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        // Opt the OpenGL surface into best-resolution + extended dynamic range.
        // Set via KVC: the typed properties are deprecated (OpenGL), and KVC
        // avoids the deprecation warnings for these intentional, unavoidable uses.
        setValue(true, forKey: "wantsBestResolutionOpenGLSurface")
        setValue(true, forKey: "wantsExtendedDynamicRangeOpenGLSurface")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func makeBackingLayer() -> CALayer { viewLayer }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Window sizing

    /// Resize the window so its content matches the video's native size (in
    /// points), clamped to the visible screen, and lock the aspect ratio so the
    /// video fills the content with no letterboxing.
    func resizeWindow(toVideoWidth w: Int, height h: Int) {
        guard w > 0, h > 0, let window = window else { return }
        let scale = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2.0
        let aspect = CGFloat(w) / CGFloat(h)

        var widthPt = CGFloat(w) / scale
        var heightPt = CGFloat(h) / scale

        if let visible = window.screen?.visibleFrame {
            let maxW = visible.width * 0.95
            let maxH = visible.height * 0.95
            if widthPt > maxW { widthPt = maxW; heightPt = widthPt / aspect }
            if heightPt > maxH { heightPt = maxH; widthPt = heightPt * aspect }
        }

        window.contentAspectRatio = NSSize(width: w, height: h)
        window.setContentSize(NSSize(width: widthPt, height: heightPt))
        window.center()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let noModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        switch event.keyCode {
        case 3 where noModifiers:           // f -> fullscreen (ours, not mpv's)
            window?.toggleFullScreen(nil)
            return
        case 126:                           // ↑ -> volume up
            volumeHandler?(5)
            return
        case 125:                           // ↓ -> volume down
            volumeHandler?(-5)
            return
        default:
            break
        }
        // Everything else (incl. ←/→ seek) goes to mpv's default bindings.
        if let key = VideoNSView.mpvKey(from: event) {
            keyHandler?(key)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Translate an NSEvent into an mpv key name, with modifier prefixes.
    static func mpvKey(from event: NSEvent) -> String? {
        let specials: [UInt16: String] = [
            49: "SPACE", 36: "ENTER", 76: "ENTER", 53: "ESC", 51: "BS", 48: "TAB",
            123: "LEFT", 124: "RIGHT", 126: "UP", 125: "DOWN",
            115: "HOME", 119: "END", 116: "PGUP", 121: "PGDWN",
        ]
        var base: String?
        if let s = specials[event.keyCode] {
            base = s
        } else if let chars = event.charactersIgnoringModifiers, let first = chars.first,
                  !first.isNewline {
            base = String(first)
        }
        guard let key = base else { return nil }

        var prefix = ""
        let flags = event.modifierFlags
        if flags.contains(.control) { prefix += "Ctrl+" }
        if flags.contains(.option) { prefix += "Alt+" }
        if flags.contains(.command) { prefix += "Meta+" }
        // Shift is only named explicitly for special keys; for printable keys the
        // character already reflects shift.
        if flags.contains(.shift), key.count > 1 { prefix += "Shift+" }
        return prefix + key
    }
}

/// Bridges the AppKit video view into SwiftUI.
struct VideoView: NSViewRepresentable {
    let player: PlayerCore

    func makeNSView(context: Context) -> VideoNSView {
        let view = VideoNSView(renderer: player.renderer, mpv: player.mpv.handle)
        view.keyHandler = { [weak player] key in player?.sendKey(key) }
        view.volumeHandler = { [weak player] delta in player?.adjustVolume(by: delta) }
        player.attachVideoView(view)
        return view
    }

    func updateNSView(_ nsView: VideoNSView, context: Context) {}
}
