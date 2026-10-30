// Spike S4 Tier 1 — Coin itself. Unmodified Coin 4.0.10 + companion
// GLU linked against gl4es; FreeCAD's vendored QuarterWidget (pinned
// weekly-2026.09.16 snapshot, src/Gui/Quarter) used UNMODIFIED — its
// inner CustomGLWidget still requests CompatibilityProfile +
// DeprecatedFunctions exactly as upstream FreeCAD ships it. Scene is
// the canonical HelloCone: perspective camera + directional light +
// orange material + SoCone.
//
// Orbit evidence, two ways (both reported, honestly labelled):
//  1. a synthetic one-finger drag (mouse press/move/release events,
//     which is what iOS touch synthesises into) posted into the
//     widget's own event path — Quarter's navigation, if functional,
//     moves the camera;
//  2. if (1) shows no camera motion, a programmatic orbit of the
//     viewer's camera, re-rendering through the same widget.
// Pixel evidence comes from QOpenGLWidget::grabFramebuffer() on the
// widget's inner GL viewport plus the simctl screenshot the build
// script captures. The app self-quits and writes a result file.
#include <QApplication>
#include <QOpenGLWidget>
#include <QMouseEvent>
#include <QTimer>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QImage>
#include <cstdio>
#include <cmath>
#include <set>
#include <vector>

#include <Quarter/Quarter.h>
#include <Quarter/QuarterWidget.h>
#include <Inventor/SoDB.h>
#include <Inventor/nodes/SoSeparator.h>
#include <Inventor/nodes/SoCamera.h>
#include <Inventor/nodes/SoPerspectiveCamera.h>
#include <Inventor/nodes/SoDirectionalLight.h>
#include <Inventor/nodes/SoMaterial.h>
#include <Inventor/nodes/SoCone.h>
#include <Inventor/SoRenderManager.h>
#include <Inventor/SbViewportRegion.h>

#include "gl_probe.h"

using SIM::Coin3D::Quarter::QuarterWidget;

static bool g_gl4esReady = false;

static void ensureGl4es(QuarterWidget* qw)
{
    if (g_gl4esReady) return;
    auto* glw = qobject_cast<QOpenGLWidget*>(qw->viewport());
    if (!glw) { std::printf("S4T1: viewport is not a QOpenGLWidget\n"); return; }
    if (!glw->context()) { std::printf("S4T1: viewport context not created yet — deferring\n"); return; }
    glw->makeCurrent();
    // gl4es COMPILE.md (iOS): initialise immediately after the GLES
    // context is current, before any desktop-GL call. Coin's first GL
    // call happens at first redraw, which has not happened yet.
    s4InitGl4es();
    std::printf("S4T1: gl4es initialised on Qt context; GL_VERSION=%s RENDERER=%s\n",
                s4GlVersion(), s4GlRenderer());
    glw->doneCurrent();
    g_gl4esReady = true;
}

// Safety net: if the first paint reaches the viewport before the
// post-show ensureGl4es() ran (platform expose ordering), initialise
// gl4es from the paint event filter — filters run before the widget's
// own paintEvent, hence before any Coin GL call.
class GlInitFilter : public QObject {
public:
    explicit GlInitFilter(QuarterWidget* qw) : QObject(qw), m_qw(qw) {}
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (ev->type() == QEvent::Paint && !g_gl4esReady) ensureGl4es(m_qw);
        return QObject::eventFilter(obj, ev);
    }
private:
    QuarterWidget* m_qw;
};

struct ImgStats {
    long conePx = 0; long totalPx = 0;
    int distinct = 0; int lumMin = 255, lumMax = 0; double lumStd = 0.0;
};

static ImgStats statsOf(const QImage& imgIn)
{
    QImage img = imgIn.convertToFormat(QImage::Format_RGBA8888);
    ImgStats s; s.totalPx = (long)img.width() * img.height();
    std::set<unsigned int> colours; std::vector<int> lums; double sum = 0;
    for (int y = 0; y < img.height(); ++y) {
        const unsigned char* line = img.constScanLine(y);
        for (int x = 0; x < img.width(); ++x) {
            const unsigned char* p = line + (size_t)x * 4;
            if (p[0] > 90 && p[0] > p[1] + 25 && p[1] > p[2] + 10) ++s.conePx;
            if ((x % 3 == 0) && (y % 3 == 0)) {
                colours.insert(((unsigned)p[0] << 16) | ((unsigned)p[1] << 8) | p[2]);
                int lum = (p[0] * 299 + p[1] * 587 + p[2] * 114) / 1000;
                if (lum < s.lumMin) s.lumMin = lum;
                if (lum > s.lumMax) s.lumMax = lum;
                sum += lum; lums.push_back(lum);
            }
        }
    }
    s.distinct = (int)colours.size();
    if (!lums.empty()) {
        double mean = sum / lums.size(), var = 0;
        for (int L : lums) var += (L - mean) * (L - mean);
        s.lumStd = std::sqrt(var / lums.size());
    }
    return s;
}

static double frameDiffFrac(const QImage& aIn, const QImage& bIn)
{
    QImage a = aIn.convertToFormat(QImage::Format_RGBA8888);
    QImage b = bIn.convertToFormat(QImage::Format_RGBA8888);
    if (a.size() != b.size()) return -1.0;
    long diff = 0, n = 0;
    for (int y = 0; y < a.height(); y += 2) {
        const unsigned char* la = a.constScanLine(y);
        const unsigned char* lb = b.constScanLine(y);
        for (int x = 0; x < a.width(); x += 2) {
            const unsigned char* pa = la + (size_t)x * 4;
            const unsigned char* pb = lb + (size_t)x * 4;
            if (std::abs((int)pa[0] - pb[0]) + std::abs((int)pa[1] - pb[1]) + std::abs((int)pa[2] - pb[2]) > 36) ++diff;
            ++n;
        }
    }
    return n ? (double)diff / n : 0.0;
}

int main(int argc, char** argv)
{
    QApplication app(argc, argv);
    SIM::Coin3D::Quarter::Quarter::init(true);

    auto* qw = new QuarterWidget();
    qw->setBackgroundColor(QColor(13, 13, 31));
    qw->resize(700, 700);
    qw->setWindowTitle("S4 Tier1 HelloCone via QuarterWidget");
    // NOTE: no gl4es init here — the viewport's QOpenGLContext does not
    // exist until the widget is shown; the fix-20 run died inside
    // gl4es's hardware test called from this spot (no current context).
    qw->viewport()->installEventFilter(new GlInitFilter(qw));

    // HelloCone scene (self-contained camera + light, as in the
    // canonical Inventor Mentor example).
    auto* root = new SoSeparator;
    auto* cam = new SoPerspectiveCamera;
    cam->position.setValue(0.f, 0.f, 5.f);
    cam->pointAt(SbVec3f(0.f, 0.f, 0.f));
    root->addChild(cam);
    auto* light = new SoDirectionalLight;
    light->direction.setValue(-1.f, -1.f, -1.f);
    light->intensity.setValue(1.0f);
    root->addChild(light);
    auto* mat = new SoMaterial;
    mat->diffuseColor.setValue(1.0f, 0.45f, 0.10f);
    mat->ambientColor.setValue(0.15f, 0.07f, 0.02f);
    mat->specularColor.setValue(0.3f, 0.3f, 0.3f);
    mat->shininess.setValue(0.3f);
    root->addChild(mat);
    auto* cone = new SoCone; // radius 1, height 2 by default
    root->addChild(cone);
    root->ref();

    qw->setSceneGraph(root);
    qw->show();
    ensureGl4es(qw);
    qw->viewAll();

    QImage frameA, frameB, frameC;
    ImgStats stA, stB, stC;
    double diffDrag = -1, diffOrbit = -1;
    bool dragMovedCamera = false;
    int glErrors = -1;

    // t=3s: capture frame A; then synthetic one-finger drag across the
    // viewport through Quarter's own event handling.
    QTimer::singleShot(3000, qw, [&]() {
        auto* glw = qobject_cast<QOpenGLWidget*>(qw->viewport());
        frameA = glw->grabFramebuffer();
        stA = statsOf(frameA);
        std::printf("S4T1: frame A captured %dx%d coneFrac=%.4f distinct=%d\n",
                    frameA.width(), frameA.height(),
                    stA.totalPx ? (double)stA.conePx / stA.totalPx : 0.0, stA.distinct);
        const QPoint start(qw->width() / 2 - 120, qw->height() / 2);
        const QPoint end(qw->width() / 2 + 120, qw->height() / 2);
        QWidget* vp = qw->viewport();
        QMouseEvent press(QEvent::MouseButtonPress, start, vp->mapToGlobal(start),
                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QApplication::sendEvent(vp, &press);
        for (int i = 1; i <= 10; ++i) {
            QPoint p = start + (end - start) * i / 10;
            QMouseEvent move(QEvent::MouseMove, p, vp->mapToGlobal(p),
                             Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            QApplication::sendEvent(vp, &move);
        }
        QMouseEvent release(QEvent::MouseButtonRelease, end, vp->mapToGlobal(end),
                            Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        QApplication::sendEvent(vp, &release);
        qw->redraw();
    });

    // t=6s: capture frame B (post-drag). If the drag did not move the
    // image, orbit the viewer's camera programmatically instead.
    QTimer::singleShot(6000, qw, [&]() {
        auto* glw = qobject_cast<QOpenGLWidget*>(qw->viewport());
        frameB = glw->grabFramebuffer();
        stB = statsOf(frameB);
        diffDrag = frameDiffFrac(frameA, frameB);
        dragMovedCamera = diffDrag > 0.01;
        std::printf("S4T1: frame B captured; diffDrag=%.4f dragMoved=%d\n",
                    diffDrag, (int)dragMovedCamera);
        if (!dragMovedCamera) {
            SoCamera* c = qw->getSoRenderManager() ? qw->getSoRenderManager()->getCamera() : nullptr;
            if (c) {
                SbRotation spin(SbVec3f(0.f, 1.f, 0.f), 0.6f);
                SbVec3f pos = c->position.getValue();
                SbMatrix m; m.setRotate(spin);
                SbVec3f newPos; m.multVecMatrix(pos, newPos);
                c->position.setValue(newPos);
                c->orientation.setValue(spin * c->orientation.getValue());
                c->pointAt(SbVec3f(0.f, 0.f, 0.f));
                std::printf("S4T1: programmatic camera orbit applied\n");
            }
            qw->redraw();
        }
    });

    // t=9s: capture frame C, drain GL errors, write verdict inputs.
    QTimer::singleShot(9000, qw, [&]() {
        auto* glw = qobject_cast<QOpenGLWidget*>(qw->viewport());
        frameC = glw->grabFramebuffer();
        stC = statsOf(frameC);
        diffOrbit = frameDiffFrac(frameB, frameC);
        glw->makeCurrent();
        glErrors = s4GlErrorCount();
        glw->doneCurrent();

        const ImgStats& st = stC.totalPx ? stC : stA;
        double coneFrac = st.totalPx ? (double)st.conePx / st.totalPx : 0.0;
        bool rendered = coneFrac > 0.02 && coneFrac < 0.60
                        && st.distinct >= 32 && (st.lumMax - st.lumMin) > 40;
        bool moved = (diffDrag > 0.01) || (diffOrbit > 0.01);
        bool pass = rendered && moved && glErrors == 0;

        QString report;
        QTextStream ts(&report);
        ts << "S4 TIER1 RESULT\n"
           << "pass=" << (pass ? "YES" : "NO") << "\n"
           << "rendered_ok=" << (rendered ? "YES" : "NO") << "\n"
           << "gl_version=" << s4GlVersion() << "\n"
           << "gl_renderer=" << s4GlRenderer() << "\n"
           << "gl_errors_after_renders=" << glErrors << "\n"
           << "frame_size=" << st.totalPx << "\n"
           << "cone_fraction=" << QString::number(coneFrac, 'f', 4) << "\n"
           << "distinct_colours_sampled=" << st.distinct << "\n"
           << "lum_min=" << st.lumMin << " lum_max=" << st.lumMax
           << " lum_std=" << QString::number(st.lumStd, 'f', 2) << "\n"
           << "drag_diff_fraction=" << QString::number(diffDrag, 'f', 4) << "\n"
           << "drag_moved_camera=" << (dragMovedCamera ? "YES" : "NO") << "\n"
           << "orbit_diff_fraction=" << QString::number(diffOrbit, 'f', 4) << "\n";
        std::printf("%s", qPrintable(report));
        std::fflush(stdout);
        frameC.save(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/s4_tier1_frame.png");
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        QDir().mkpath(dir);
        QFile f(dir + "/s4_tier1_result.txt");
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) { QTextStream(&f) << report; f.close(); }
        app.exit(pass ? 0 : 3);
    });
    return app.exec();
}
