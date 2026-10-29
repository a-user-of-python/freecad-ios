#pragma once
// Spike shim — NOT FreeCAD source. FreeCAD's vendored QuarterWidget.cpp
// includes <Base/Profiler.h>. It uses no Profiler class API, but it DOES
// use the Tracy macros ZoneScoped (x2) and FrameMark (x1) that the real
// header provides (a first version of this shim missed them — CI caught
// it). In a Tracy-less FreeCAD build these macros are no-ops; provide
// exactly those no-op forms so the vendored Quarter sources compile
// UNMODIFIED in the spike harness.
#ifndef ZoneScoped
#define ZoneScoped
#endif
#ifndef ZoneScopedN
#define ZoneScopedN(x)
#endif
#ifndef ZoneScopedC
#define ZoneScopedC(x)
#endif
#ifndef FrameMark
#define FrameMark
#endif
#ifndef TracyPlot
#define TracyPlot(x, y)
#endif
