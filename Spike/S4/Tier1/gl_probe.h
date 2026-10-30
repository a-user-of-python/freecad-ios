// Tier 1 GL probe: the only TU that includes gl4es headers directly.
// The vendored Quarter sources include <GL/gl.h> themselves (resolved
// to gl4es), but app code uses this probe for init/error/version so
// the app TU stays Qt+Coin only.
#pragma once

// Calls gl4es's initialize_gl4es(). Call with a GLES context current.
void s4InitGl4es();
// Drains and returns the glGetError count (through gl4es).
int s4GlErrorCount();
// glGetString(GL_VERSION / GL_RENDERER) through gl4es, as C strings
// in static buffers.
const char* s4GlVersion();
const char* s4GlRenderer();

// Diagnostic (fix 22): draws the Tier-0 lit fixed-function triangle
// through raw gl4es calls into the currently bound framebuffer of size
// w x h, then reads pixels back. Returns lit-pixel count; centre RGB
// written to centre[3]. Proves whether the widget FBO/context path can
// draw at all at the moment Coin renders nothing.
long s4DrawProbeTriangle(int w, int h, int centre[3]);
// Reads back the whole w x h framebuffer and counts cone-orange
// pixels after whatever was last drawn (e.g. a forced Coin render).
long s4CountConePixels(int w, int h, int centre[3]);
