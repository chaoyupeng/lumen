import AppKit
import CoreGraphics
import CoreVideo
import OpenGL
import OpenGL.GL3
import QuartzCore

/// CAOpenGLLayer subclass hosting mpv's OpenGL render output. Uses a float
/// (64-bit) color buffer so HDR has the precision to avoid banding; the
/// resulting bit depth is fed to mpv via MPV_RENDER_PARAM_DEPTH. EDR is enabled
/// by setting `colorspace` + `wantsExtendedDynamicRangeContent` (mirrors IINA).
final class ViewLayer: CAOpenGLLayer {
    let renderer: MPVRenderer
    var mpvHandle: OpaquePointer?

    /// The view hosting this layer, used to find the current NSScreen for the
    /// EDR capability check.
    weak var hostView: NSView?

    private let pixelFormatObj: CGLPixelFormatObj
    /// 16 when a float color buffer was obtained, else 8. Passed to mpv each frame.
    private let bufferDepth: GLint

    init(renderer: MPVRenderer) {
        self.renderer = renderer
        (self.pixelFormatObj, self.bufferDepth) = ViewLayer.makePixelFormat()
        super.init()
        renderer.layer = self
        isOpaque = true
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    override init(layer: Any) {
        let other = layer as! ViewLayer
        self.renderer = other.renderer
        self.mpvHandle = other.mpvHandle
        self.hostView = other.hostView
        self.pixelFormatObj = other.pixelFormatObj
        self.bufferDepth = other.bufferDepth
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    var hostScreen: NSScreen? { hostView?.window?.screen }

    // MARK: - Pixel format (float color buffer for HDR precision)

    private static func makePixelFormat() -> (CGLPixelFormatObj, GLint) {
        let floatAttribs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAColorSize, CGLPixelFormatAttribute(64),
            kCGLPFAColorFloat,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        var pix: CGLPixelFormatObj?
        var count: GLint = 0
        if CGLChoosePixelFormat(floatAttribs, &pix, &count) == kCGLNoError, let pix = pix {
            return (pix, 16)
        }
        // Fallback: 8-bit, no float.
        let baseAttribs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0),
        ]
        pix = nil
        count = 0
        CGLChoosePixelFormat(baseAttribs, &pix, &count)
        return (pix!, 8)
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        pixelFormatObj
    }

    // MARK: - EDR / HDR

    /// Enable EDR output. Must be called on the main thread.
    func enableHDR(colorSpaceName: CFString) {
        colorspace = CGColorSpace(name: colorSpaceName)
        wantsExtendedDynamicRangeContent = true
        setNeedsDisplay()
    }

    /// Return to SDR output. Must be called on the main thread.
    func disableHDR() {
        colorspace = hostScreen?.colorSpace?.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        wantsExtendedDynamicRangeContent = false
        setNeedsDisplay()
    }

    // MARK: - Drawing

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

        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &fbo)

        let pxWidth = Int(bounds.width * contentsScale)
        let pxHeight = Int(bounds.height * contentsScale)
        renderer.render(fbo: fbo, width: pxWidth, height: pxHeight, depth: bufferDepth)

        CGLUnlockContext(ctx)
    }
}
