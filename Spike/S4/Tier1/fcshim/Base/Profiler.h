#pragma once
// Spike shim — NOT FreeCAD source. FreeCAD's vendored QuarterWidget.cpp
// includes <Base/Profiler.h> but uses nothing from it (verified by grep
// of the pinned snapshot). This empty header satisfies the include so
// the vendored Quarter sources compile UNMODIFIED in the spike harness.
