import AppKit
import CoreVideo
import OpenGL
import OpenGL.GL3
import QuartzCore

/// CAOpenGLLayer subclass that hosts mpv's OpenGL render output. Core Animation
/// calls `draw(inCGLContext:)` on its own thread with the context current and
/// locked; we forward to the renderer. EDR/colorspace state is applied here in
/// a later step (refreshEDR) — for now it produces a correct SDR/HDR-passthrough
/// picture.
final class ViewLayer: CAOpenGLLayer {
    let renderer: MPVRenderer
    var mpvHandle: OpaquePointer?

    init(renderer: MPVRenderer) {
        self.renderer = renderer
        super.init()
        renderer.layer = self
        isOpaque = true
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    // Core Animation makes presentation copies via init(layer:); preserve refs.
    override init(layer: Any) {
        let other = layer as! ViewLayer
        self.renderer = other.renderer
        self.mpvHandle = other.mpvHandle
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        if let pixelFormat = pixelFormat { return pixelFormat }
        return super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    override func canDraw(inCGLContext ctx: CGLContextObj,
                          pixelFormat pf: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval,
                          displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        mpvHandle != nil
    }

    override func draw(inCGLContext ctx: CGLContextObj,
                       pixelFormat pf: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval,
                       displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let mpv = mpvHandle else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }
        CGLLockContext(ctx)
        CGLSetCurrentContext(ctx)
        renderer.createIfNeeded(mpv: mpv)

        // CAOpenGLLayer binds its own framebuffer before calling draw; query it
        // rather than assuming FBO 0.
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fbo)

        let pxWidth = Int(bounds.width * contentsScale)
        let pxHeight = Int(bounds.height * contentsScale)
        renderer.render(fbo: fbo, width: pxWidth, height: pxHeight)

        CGLUnlockContext(ctx)
        // CAOpenGLLayer performs the buffer flush after this method returns.
    }
}
