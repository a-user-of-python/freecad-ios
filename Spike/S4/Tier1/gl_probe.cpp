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

long s4DrawProbeTriangle(int w, int h, int centre[3])
{
    glViewport(0, 0, w, h);
    glClearColor(0.05f, 0.05f, 0.12f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glFrustum(-1.0, 1.0, -1.0, 1.0, 2.0, 10.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glTranslatef(0.f, 0.f, -5.f);
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_DEPTH_TEST);
    const float pos[4] = { 2.f, 3.f, 4.f, 0.f };
    glLightfv(GL_LIGHT0, GL_POSITION, pos);
    const float amb[4] = { 0.2f, 0.2f, 0.2f, 1.f };
    const float dif[4] = { 1.f, 1.f, 1.f, 1.f };
    glLightfv(GL_LIGHT0, GL_AMBIENT, amb);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, dif);
    const float mat[4] = { 1.0f, 0.45f, 0.10f, 1.f };
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, mat);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, mat);
    glBegin(GL_TRIANGLES);
    glNormal3f(0.f, 0.f, 1.f); glVertex3f(-1.2f, -1.0f, 0.f);
    glNormal3f(0.f, 0.f, 1.f); glVertex3f( 1.2f, -1.0f, 0.f);
    glNormal3f(0.f, 0.f, 1.f); glVertex3f( 0.0f,  1.2f, 0.f);
    glEnd();
    glFlush();
    static unsigned char* buf = nullptr;
    static long cap = 0;
    long need = (long)w * h * 4;
    if (need > cap) { delete[] buf; buf = new unsigned char[need]; cap = need; }
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    long lit = 0;
    for (long i = 0; i < (long)w * h; ++i) {
        const unsigned char* p = buf + i * 4;
        if (p[0] > 90 && p[0] > p[1] + 25 && p[1] > p[2] + 10) ++lit;
    }
    const unsigned char* c = buf + ((long)(h / 2) * w + w / 2) * 4;
    centre[0] = c[0]; centre[1] = c[1]; centre[2] = c[2];
    return lit;
}

long s4CountConePixels(int w, int h, int centre[3])
{
    static unsigned char* buf = nullptr;
    static long cap = 0;
    long need = (long)w * h * 4;
    if (need > cap) { delete[] buf; buf = new unsigned char[need]; cap = need; }
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);
    long lit = 0;
    for (long i = 0; i < (long)w * h; ++i) {
        const unsigned char* p = buf + i * 4;
        if (p[0] > 90 && p[0] > p[1] + 25 && p[1] > p[2] + 10) ++lit;
    }
    const unsigned char* c = buf + ((long)(h / 2) * w + w / 2) * 4;
    centre[0] = c[0]; centre[1] = c[1]; centre[2] = c[2];
    return lit;
}
