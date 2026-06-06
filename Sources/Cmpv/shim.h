// Umbrella header exposing libmpv (Homebrew) to Swift via the Cmpv module.
// render.h + render_gl.h provide the OpenGL render API used for in-process,
// EDR-capable video output into a CAOpenGLLayer.
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>
