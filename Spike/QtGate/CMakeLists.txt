# Qt-gate battery — synthesis §1.3 deciding experiment, isolated half.
#
# Replicates, against the Qt iOS kit, EXACTLY what the pinned FreeCAD
# snapshot's cMake/FreeCAD_Helpers/SetupQt.cmake does at configure time
# (Qt6 + BUILD_GUI component list), then COMPILES code exercising the
# precise Qt APIs the snapshot selects on its newest version branches:
#
#   src/Gui/BitmapFactory.cpp:788   #if QT_VERSION < 6.9.0 mirror()
#                                   #else QImage::flip(Qt::Vertical)
#   src/Gui/NaviCube.cpp:774        #else QImage::flipped(Qt::Vertical)
#   src/Gui/View3DInventorViewer.cpp:407  #else flipped(Qt::Vertical)
#   src/Gui/PreferencePages/DlgSettingsPDF.cpp
#                                   #if >= 6.8.0 PdfVersion_X4
#   src/Gui/Dialogs/DlgExpressionInput.cpp
#                                   #if >= 6.7.0 QCheckBox::checkStateChanged
#
# QImage::flip/flipped are Qt 6.9 APIs: they exist in 6.9.3 and NOT in
# 6.8.3, so this battery also discriminates the fallback kit. A failure
# here on an API that only exists in Qt >= 6.10 would be a [QT-API]
# gate failure; a missing component is [DEP]/[CONFIG] (kit module or
# host-path), never silently a gate failure — the classifier decides
# from the logs this project emits.
cmake_minimum_required(VERSION 3.24)
project(qtgate_battery CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)

# --- SetupQt.cmake's component list, verbatim for Qt6 + BUILD_GUI ---
# Base: Core Concurrent Network Xml; GUI adds GuiTools SvgWidgets
# OpenGLWidgets OpenGL PrintSupport Svg UiTools Widgets LinguistTools.
# GuiTools is probed separately: it is a host-tools package, and on the
# aqt iOS kit it may legitimately resolve only via QT_HOST_PATH — that
# outcome is [CONFIG], recorded, not fatal to the battery.
find_package(Qt6 REQUIRED COMPONENTS
    Core Concurrent Network Xml
    SvgWidgets OpenGLWidgets OpenGL PrintSupport Svg UiTools Widgets
    LinguistTools)
find_package(Qt6 QUIET COMPONENTS GuiTools)
if(Qt6GuiTools_FOUND)
    message(STATUS "QTGATE: GuiTools FOUND (target kit)")
else()
    message(STATUS "QTGATE: GuiTools NOT in target kit (host-path item, [CONFIG] candidate)")
endif()
message(STATUS "QTGATE: Qt version under test: ${Qt6Core_VERSION}")
message(STATUS "QTGATE: all REQUIRED SetupQt components found")

# FreeCAD's rcc options (SetupQt.cmake FREECAD_RCC_OPTIONS), passed
# exactly the way src/Gui/CMakeLists.txt passes them — the variable
# form of qt_add_resources with OPTIONS. RUN 40962937748 FINDING:
# FreeCAD's default algorithm is zstd, but the official Qt 6.9.3
# host rcc answers "Zstandard support not compiled in" (its
# --compress-algo accepts only [zlib], none) — a [CONFIG] item whose
# remedy is FreeCAD's own cache variable
# FREECAD_RCC_COMPRESSION_ALGO=zlib, NOT a Qt-API gap. The probe
# script exercises the zstd form directly (rcc-zstd-probe.log,
# non-fatal); this battery uses zlib so the version-branch TU below
# actually compiles and links.
qt_add_resources(QTGATE_RES_SRCS res.qrc
    OPTIONS --compress-algo zlib --compress 19 --threshold 70)
message(STATUS "QTGATE: rcc resource step configured (zlib; zstd probed separately)")

qt_add_executable(qtgate_battery main.cpp widget.ui ${QTGATE_RES_SRCS})
target_link_libraries(qtgate_battery PRIVATE
    Qt6::Core Qt6::Concurrent Qt6::Network Qt6::Xml
    Qt6::SvgWidgets Qt6::OpenGLWidgets Qt6::OpenGL Qt6::PrintSupport
    Qt6::Svg Qt6::UiTools Qt6::Widgets)

# LinguistTools: FreeCAD calls qt_add_translation on its .ts files.
qt_add_translation(QTGATE_QM_FILES dummy.ts)
message(STATUS "QTGATE: LinguistTools translation step configured: ${QTGATE_QM_FILES}")
