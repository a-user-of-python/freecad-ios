// S0 toolchain smoke app: the smallest real Qt Widgets program.
// Proves the iOS kit can configure, compile, link (static Qt incl.
// the QIOSIntegration platform plugin) and bundle an executable.
#include <QApplication>
#include <QLabel>
#include <QWidget>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QWidget window;
    window.setWindowTitle(QStringLiteral("S0 Smoke"));
    auto *label = new QLabel(QStringLiteral("FreeCAD iPad port — S0 toolchain smoke"), &window);
    label->setAlignment(Qt::AlignCenter);
    window.resize(480, 320);
    window.show();
    return app.exec();
}
