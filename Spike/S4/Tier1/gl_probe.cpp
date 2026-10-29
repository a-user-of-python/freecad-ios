#include "gl_probe.h"
#include <GL/gl.h>
#include <cstdio>

extern "C" void initialize_gl4es(void);

void s4InitGl4es()
{
    initialize_gl4es();
}

int s4GlErrorCount()
{
    int n = 0;
    while (glGetError() != GL_NO_ERROR) ++n;
    return n;
}

const char* s4GlVersion()
{
    const unsigned char* s = glGetString(GL_VERSION);
    return s ? reinterpret_cast<const char*>(s) : "(null)";
}

const char* s4GlRenderer()
{
    const unsigned char* s = glGetString(GL_RENDERER);
    return s ? reinterpret_cast<const char*>(s) : "(null)";
}
