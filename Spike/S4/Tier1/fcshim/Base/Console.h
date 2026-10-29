#pragma once
// Spike shim — NOT FreeCAD source. Minimal stand-in for FreeCAD's
// Base::Console singleton, covering only the surface the vendored
// SoQTQuarterAdaptor uses (printf-style log/warning calls), so the
// vendored Quarter sources compile and link UNMODIFIED in the harness.
#include <cstdio>
namespace Base {
class ConsoleSingleton {
public:
    template<typename... A> void log(A&&...) {}
    template<typename... A> void warning(A&&...) { std::fprintf(stderr, "[Quarter warning]\n"); }
    template<typename... A> void error(A&&...) { std::fprintf(stderr, "[Quarter error]\n"); }
    template<typename... A> void message(A&&...) {}
};
inline ConsoleSingleton& Console() {
    static ConsoleSingleton instance;
    return instance;
}
} // namespace Base
