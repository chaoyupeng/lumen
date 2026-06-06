import Cmpv
import Foundation
import OpenGL
import OpenGL.GL3

/// Resolves OpenGL function pointers for libmpv. Must be a non-capturing C
/// function. On macOS the GL symbols live in the system OpenGL framework.
private func mpvGetProcAddress(_ ctx: UnsafeMutableRawPointer?,
                               _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name = name else { return nil }
    let symbol = String(cString: name) as CFString
    let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}

/// Called by libmpv (on an arbitrary thread) when a new frame should be drawn.
/// ADVANCED_CONTROL contract: we may NOT re-enter mpv_render_context_* here —
/// only schedule a redraw.
private func mpvRenderUpdate(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx = ctx else { return }
    Unmanaged<MPVRenderer>.fromOpaque(ctx).takeUnretainedValue().scheduleRedraw()
}

/// Owns the `mpv_render_context` and the OpenGL plumbing. The actual GL draw
/// happens inside `ViewLayer.draw(inCGLContext:)`, which calls `render(...)`.
final class MPVRenderer {
    private var renderContext: OpaquePointer?
    private var created = false

    /// The layer to invalidate when mpv has a new frame. Set by ViewLayer.
    weak var layer: ViewLayer?

    /// Called on the main thread once the render context exists. The player
    /// uses this to flush a file open that was requested before the surface
    /// was ready (otherwise mpv's vo=libmpv fails with "No render context set").
    var onReady: (() -> Void)?

    /// Lazily create the render context. Called from inside the layer's draw,
    /// where a CGL context is current.
    func createIfNeeded(mpv: OpaquePointer) {
        guard !created else { return }
        created = true

        let apiType = strdup("opengl") // MPV_RENDER_API_TYPE_OPENGL
        defer { free(apiType) }

        var initParams = mpv_opengl_init_params(get_proc_address: mpvGetProcAddress,
                                                get_proc_address_ctx: nil)
        var advanced: CInt = 1

        withUnsafeMutablePointer(to: &initParams) { ip in
            withUnsafeMutablePointer(to: &advanced) { ap in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                     data: UnsafeMutableRawPointer(apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                                     data: UnsafeMutableRawPointer(ip)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL,
                                     data: UnsafeMutableRawPointer(ap)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                var ctx: OpaquePointer?
                let rc = mpv_render_context_create(&ctx, mpv, &params)
                if rc >= 0, let ctx = ctx {
                    renderContext = ctx
                    mpv_render_context_set_update_callback(
                        ctx, mpvRenderUpdate, Unmanaged.passUnretained(self).toOpaque())
                    DispatchQueue.main.async { [weak self] in self?.onReady?() }
                } else {
                    NSLog("Lumen: mpv_render_context_create failed (\(rc))")
                }
            }
        }
    }

    fileprivate func scheduleRedraw() {
        guard let layer = layer else { return }
        DispatchQueue.main.async { layer.setNeedsDisplay() }
    }

    /// Render one frame into the given framebuffer. Must be called with the
    /// destination GL context current (ViewLayer guarantees this). `depth` is
    /// the color-buffer bit depth (16 for the float format, else 8) so mpv can
    /// dither correctly for HDR.
    func render(fbo: GLint, width: Int, height: Int, depth: GLint) {
        guard let ctx = renderContext else { return }
        var fboParam = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(width), h: Int32(height),
                                      internal_format: 0)
        var flipY: CInt = 1
        var depthParam: CInt = CInt(depth)
        withUnsafeMutablePointer(to: &fboParam) { fp in
            withUnsafeMutablePointer(to: &flipY) { yp in
                withUnsafeMutablePointer(to: &depthParam) { dp in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO,
                                         data: UnsafeMutableRawPointer(fp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y,
                                         data: UnsafeMutableRawPointer(yp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_DEPTH,
                                         data: UnsafeMutableRawPointer(dp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    mpv_render_context_render(ctx, &params)
                }
            }
        }
    }

    /// Teardown ordering matters (the #1 in-process libmpv crash source):
    /// detach the update callback FIRST so no further redraws are scheduled,
    /// then free the context. Call this before MPVClient.terminate().
    func destroy() {
        guard let ctx = renderContext else { return }
        mpv_render_context_set_update_callback(ctx, nil, nil)
        mpv_render_context_free(ctx)
        renderContext = nil
        created = false
    }
}
