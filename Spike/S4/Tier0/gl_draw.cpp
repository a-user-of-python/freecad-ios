// Tier 0: fixed-function lit triangle through gl4es on Qt's EAGL context.
//
// Everything GL in this file goes through gl4es's headers/symbols
// (GL/gl.h from the gl4es include dir, linked against libGL.a). The
// calls used here — glBegin/glEnd, glLightfv, glMaterialfv, per-vertex
// glNormal3f — are exactly the desktop-GL fixed-function surface that
// does not exist in OpenGL ES; if pixels come back correctly shaded,
// gl4es's FPE translated them onto Qt's GLES context.
#include "gl_draw.h"

#include <GL/gl.h>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <vector>
#include <set>

extern "C" void initialize_gl4es(void);

static bool g_gl4esInit = false;

static int countErrors()
{
    int n = 0;
    while (glGetError() != GL_NO_ERROR) ++n;
    return n;
}

void tier0DrawAndReadback(int w, int h, Tier0Result* out)
{
    if (!g_gl4esInit) {
        // Per gl4es COMPILE.md (iOS): call immediately after the GLES
        // context is current — paintGL guarantees that for Qt's context.
        initialize_gl4es();
        g_gl4esInit = true;
    }
    out->width = w; out->height = h;

    const char* ver = reinterpret_cast<const char*>(glGetString(GL_VERSION));
    const char* ren = reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    std::snprintf(out->glVersion, sizeof(out->glVersion), "%s", ver ? ver : "(null)");
    std::snprintf(out->glRenderer, sizeof(out->glRenderer), "%s", ren ? ren : "(null)");

    (void)countErrors(); // drain any pre-existing errors

    glViewport(0, 0, w, h);
    glClearColor(0.05f, 0.05f, 0.12f, 1.0f); // dark blue background
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(-1.0, 1.0, -1.0, 1.0, 1.5, 10.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(0.f, 0.f, -4.f);

    // Fixed-function lighting: one directional light, orange material.
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    const float lightPos[4] = { 1.0f, 1.0f, 2.0f, 0.0f };
    const float lightDiff[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
    glLightfv(GL_LIGHT0, GL_POSITION, lightPos);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, lightDiff);
    const float matDiff[4] = { 1.0f, 0.45f, 0.10f, 1.0f };
    const float matAmb[4] = { 0.15f, 0.07f, 0.02f, 1.0f };
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, matDiff);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, matAmb);

    // One triangle; per-vertex normals fan from facing the light to
    // nearly edge-on, so a working fixed-function pipeline MUST produce
    // a luminance gradient across the face (not a flat colour).
    glBegin(GL_TRIANGLES);
        glNormal3f(0.2f, 0.2f, 1.0f);  glVertex3f(-0.9f, -0.8f, 0.0f);
        glNormal3f(0.9f, 0.1f, 0.25f); glVertex3f( 0.9f, -0.8f, 0.0f);
        glNormal3f(0.0f, 1.0f, 0.15f); glVertex3f( 0.0f,  0.9f, 0.0f);
    glEnd();
    glFinish();

    // Readback exactly as an app would: glReadPixels over the frame.
    std::vector<unsigned char> px((size_t)w * h * 4);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
    out->glErrors = countErrors();

    const int bgR = 13, bgG = 13, bgB = 31; // 0.05,0.05,0.12 * 255
    std::set<unsigned int> colours;
    double sum = 0.0; long n = 0;
    std::vector<int> lums;
    lums.reserve(1 << 15);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const unsigned char* p = &px[((size_t)y * w + x) * 4];
            int dr = std::abs((int)p[0] - bgR), dg = std::abs((int)p[1] - bgG), db = std::abs((int)p[2] - bgB);
            if (dr + dg + db > 60) { // triangle pixel
                ++out->litPixels;
                int lum = (p[0] * 299 + p[1] * 587 + p[2] * 114) / 1000;
                if (lum < out->lumMin) out->lumMin = lum;
                if (lum > out->lumMax) out->lumMax = lum;
                sum += lum; ++n;
                if ((x % 3 == 0) && (y % 3 == 0)) {
                    colours.insert(((unsigned)p[0] << 16) | ((unsigned)p[1] << 8) | p[2]);
                    lums.push_back(lum);
                }
            }
        }
    }
    out->distinctColours = (int)colours.size();
    if (n > 0) {
        double mean = sum / n, var = 0.0;
        for (int L : lums) var += (L - mean) * (L - mean);
        out->lumStd = lums.empty() ? 0.0 : std::sqrt(var / lums.size());
    }
    const unsigned char* c = &px[((size_t)(h / 2) * w + (w / 2)) * 4];
    out->centreR = c[0]; out->centreG = c[1]; out->centreB = c[2];

    // Pass criteria (synthesis S4 Tier 0, operationalised): no GL errors,
    // a substantial lit area, and REAL shading — many distinct colours
    // and a wide luminance range across the single face.
    out->pass = (out->glErrors == 0)
        && out->litPixels > (long)w * h / 20
        && out->distinctColours >= 8
        && (out->lumMax - out->lumMin) > 40
        && out->centreR > 80 && out->centreR > out->centreG && out->centreG > out->centreB;
}
