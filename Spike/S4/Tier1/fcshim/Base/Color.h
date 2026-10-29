#pragma once
// Spike shim — NOT FreeCAD source. Minimal stand-in for FreeCAD's
// Base::Color, covering only the surface the vendored
// SoQTQuarterAdaptor uses (construction from rgb floats, component
// access), so the vendored Quarter sources compile UNMODIFIED.
namespace Base {
class Color {
public:
    float r = 0.f, g = 0.f, b = 0.f, a = 1.f;
    Color() = default;
    Color(float rr, float gg, float bb, float aa = 1.f) : r(rr), g(gg), b(bb), a(aa) {}
    Color(unsigned long packed) {
        r = ((packed >> 16) & 0xff) / 255.f;
        g = ((packed >> 8) & 0xff) / 255.f;
        b = (packed & 0xff) / 255.f;
    }
};
} // namespace Base
