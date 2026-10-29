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
