import AppKit
import SwiftUI

/// The AppKit view backing the video surface. Uses ViewLayer as its backing
/// layer and is the first responder for (future) keyboard input.
final class VideoNSView: NSView {
    private let viewLayer: ViewLayer

    init(renderer: MPVRenderer, mpv: OpaquePointer?) {
        viewLayer = ViewLayer(renderer: renderer)
        viewLayer.mpvHandle = mpv
        super.init(frame: .zero)
        viewLayer.hostView = self
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        // Opt the OpenGL surface into best-resolution + extended dynamic range
        // (mirrors IINA; deprecated-but-functional alongside CAOpenGLLayer).
        wantsBestResolutionOpenGLSurface = true
        wantsExtendedDynamicRangeOpenGLSurface = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func makeBackingLayer() -> CALayer { viewLayer }

    override var acceptsFirstResponder: Bool { true }
}

/// Bridges the AppKit video view into SwiftUI.
struct VideoView: NSViewRepresentable {
    let player: PlayerCore

    func makeNSView(context: Context) -> VideoNSView {
        VideoNSView(renderer: player.renderer, mpv: player.mpv.handle)
    }

    func updateNSView(_ nsView: VideoNSView, context: Context) {}
}
