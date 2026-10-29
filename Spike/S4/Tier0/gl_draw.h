// Tier 0 draw/readback interface. The implementation TU (gl_draw.cpp)
// is the ONLY translation unit that includes gl4es headers, so Qt's
// headers and gl4es's GL/gl.h never collide in one TU.
#pragma once

struct Tier0Result {
    int glErrors = -1;
    int width = 0, height = 0;
    long litPixels = 0;      // pixels clearly different from clear colour
    int distinctColours = 0; // sampled distinct colours inside the triangle
    int lumMin = 255, lumMax = 0;
    double lumStd = 0.0;
    int centreR = -1, centreG = -1, centreB = -1;
    char glVersion[128] = "";
    char glRenderer[128] = "";
    bool pass = false;
};

// Draws one lit fixed-function triangle into the currently-current
// context's default draw buffer at (w,h), reads it back with
// glReadPixels, and fills *out. Must be called with the Qt EAGL context
// current (i.e. from QOpenGLWidget::paintGL). Calls initialize_gl4es()
// itself on first use.
void tier0DrawAndReadback(int w, int h, Tier0Result* out);
