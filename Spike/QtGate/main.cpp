// Qt-gate battery translation unit. Compile+link ONLY (never run):
// every block names the pinned-snapshot call site whose newest-branch
// API it exercises against the Qt iOS kit headers.
#include <QApplication>
#include <QCheckBox>
#include <QImage>
#include <QOpenGLFunctions>
#include <QOpenGLWidget>
#include <QPagedPaintDevice>
#include <QPrinter>
#include <QSvgWidget>
#include <QtConcurrent>
#include <QUiLoader>
#include <QXmlStreamReader>
#include <QTcpSocket>

// AUTOMOC probe: FreeCAD sets CMAKE_AUTOMOC globally (SetupQt.cmake).
class GateProbe : public QObject
{
    Q_OBJECT
public:
    int value = 0;
public slots:
    void bump() { ++value; }
signals:
    void bumped();
};

int main(int argc, char** argv)
{
    QApplication app(argc, argv);

    // src/Gui/BitmapFactory.cpp (>= 6.9.0 branch) + NaviCube.cpp ditto:
    // QImage::flip / QImage::flipped are Qt 6.9 APIs.
    QImage img(4, 4, QImage::Format_RGBA8888);
    img.flip(Qt::Vertical);
    const QImage flipped = img.flipped(Qt::Vertical);
    // <= 6.8 fallback branch must also still exist in the kit:
    QImage mirrored = img.mirrored(false, true);

    // src/Gui/PreferencePages/DlgSettingsPDF.cpp (>= 6.8.0 branch):
    const auto pdfVer = QPagedPaintDevice::PdfVersion_X4;
    QPrinter printer;
    printer.setPageLayout(QPageLayout(QPageSize(QPageSize::A4),
                                      QPageLayout::Portrait,
                                      QMarginsF(10, 10, 10, 10)));

    // src/Gui/Dialogs/DlgExpressionInput.cpp (>= 6.7.0 branch):
    QCheckBox box;
    QObject::connect(&box, &QCheckBox::checkStateChanged,
                     &app, [](Qt::CheckState) {});

    // Gui viewport stack (OpenGLWidgets): widget + functions object.
    QOpenGLWidget glWidget;
    QOpenGLFunctions glFuncs;

    // UiTools + Svg/SvgWidgets + Network + Xml + Concurrent surfaces.
    QUiLoader loader;
    QSvgWidget svgWidget;
    QTcpSocket socket;
    QXmlStreamReader xml;
    auto future = QtConcurrent::run([] { return 42; });

    GateProbe probe;
    QObject::connect(&probe, &GateProbe::bumped, &app, [] {});

    return static_cast<int>(flipped.width() + mirrored.height()
                            + static_cast<int>(pdfVer)
                            + future.result()
                            + (loader.isLanguageChangeEnabled() ? 0 : 0)
                            + svgWidget.renderer()->isValid() ? 0 : 0)
        + socket.isValid() + (xml.device() ? 1 : 0)
        + glWidget.isValid() + (glFuncs.initializeOpenGLFunctions(), 0)
        + probe.value;
}
#include "main.moc"
