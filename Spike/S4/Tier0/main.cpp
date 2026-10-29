// Spike S4 Tier 0 — plumbing. One QOpenGLWidget; after Qt's EAGL
// context is current, gl4es draws one lit fixed-function triangle and
// the app reads the pixels back and asserts the shading happened.
// Results go to stdout (simctl --console) and to a result file in the
// app sandbox Documents dir (pulled by the build script via simctl
// get_app_container). The app quits by itself ~10 s after the first
// verified frame so CI never hangs on it.
#include <QApplication>
#include <QOpenGLWidget>
#include <QSurfaceFormat>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QTimer>
#include <cstdio>

#include "gl_draw.h"

class TriWidget : public QOpenGLWidget {
public:
    explicit TriWidget(QWidget* parent = nullptr) : QOpenGLWidget(parent) {}
    Tier0Result result;
    bool done = false;
protected:
    void paintGL() override {
        Tier0Result r;
        tier0DrawAndReadback(width() * (int)devicePixelRatioF(),
                             height() * (int)devicePixelRatioF(), &r);
        if (!done) { result = r; done = true; }
    }
};

int main(int argc, char** argv)
{
    QApplication app(argc, argv);
    TriWidget w;
    w.resize(600, 600);
    w.setWindowTitle("S4 Tier0 gl4es triangle");
    w.show();

    QTimer::singleShot(10000, &app, [&]() {
        const Tier0Result& r = w.result;
        QString report;
        QTextStream ts(&report);
        ts << "S4 TIER0 RESULT\n"
           << "pass=" << (r.pass ? "YES" : "NO") << "\n"
           << "gl_version=" << r.glVersion << "\n"
           << "gl_renderer=" << r.glRenderer << "\n"
           << "gl_errors=" << r.glErrors << "\n"
           << "frame=" << r.width << "x" << r.height << "\n"
           << "lit_pixels=" << r.litPixels << "\n"
           << "distinct_colours_sampled=" << r.distinctColours << "\n"
           << "lum_min=" << r.lumMin << " lum_max=" << r.lumMax
           << " lum_std=" << QString::number(r.lumStd, 'f', 2) << "\n"
           << "centre_rgb=" << r.centreR << "," << r.centreG << "," << r.centreB << "\n"
           << "surface_renderable_type=" << (int)w.format().renderableType()
           << " surface_major=" << w.format().majorVersion()
           << " surface_minor=" << w.format().minorVersion() << "\n";
        std::printf("%s", qPrintable(report));
        std::fflush(stdout);
        const QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        QDir().mkpath(dir);
        QFile f(dir + "/s4_tier0_result.txt");
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream(&f) << report;
            f.close();
        }
        app.exit(r.pass ? 0 : 3);
    });
    return app.exec();
}
