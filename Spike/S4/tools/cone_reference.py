#!/usr/bin/env python3
"""Independent ground-truth reference for S4 Tier 1's HelloCone scene.

A small analytic software renderer (pure stdlib): raycasts the same
scene the Tier 1 app builds — SoCone defaults (base radius 1, height 2,
apex +Y, base at y=-1) from a perspective camera at (0,0,5) aimed at
the origin, one directional light shining from (1,1,1) direction
(SoDirectionalLight direction (-1,-1,-1)), orange diffuse material
(1.0, 0.45, 0.10) with the same ambient term — over the same dark-blue
background. Emits reference PNG + pixel statistics computed with the
SAME thresholds as tools/png_stats.py, so simulator screenshots and
this reference are compared side-by-side on equal terms.

This is a statistical ground truth (silhouette fraction, shading
spread), not a pixel-exact oracle: Quarter/Coin add a headlight and
their own camera framing (viewAll), so bands, not equality, are the
comparison. Method stated in the S4 verdict.
"""
import json, math, struct, sys, zlib

W = H = 400
BG = (13, 13, 31)
DIFFUSE = (1.0, 0.45, 0.10)
AMBIENT = (0.15, 0.07, 0.02)
LIGHT_DIR = tuple(v / math.sqrt(3) for v in (1.0, 1.0, 1.0))  # from surface toward light
CAM = (0.0, 0.0, 5.0)
FOV = math.radians(45.0)

def cone_intersect(o, d):
    """Ray vs closed cone: apex (0,1,0), base circle y=-1 r=1.
    Returns (t, normal) or None. Side: x^2+z^2 = ((1-y)/2)^2 for y in [-1,1]."""
    best = None
    # side: substitute; k = (1-y)/2 => x^2+z^2 - k^2 = 0
    # y = oy + t dy ; k = (1 - oy - t*dy)/2
    ox, oy, oz = o; dx, dy, dz = d
    a0, a1 = (1 - oy) / 2.0, -dy / 2.0
    A = dx*dx + dz*dz - a1*a1
    B = 2*(ox*dx + oz*dz - a0*a1)
    C = ox*ox + oz*oz - a0*a0
    disc = B*B - 4*A*C
    if abs(A) > 1e-12 and disc >= 0:
        sq = math.sqrt(disc)
        for t in ((-B - sq)/(2*A), (-B + sq)/(2*A)):
            if t > 1e-6:
                y = oy + t*dy
                if -1.0 <= y <= 1.0:
                    x, z = ox + t*dx, oz + t*dz
                    r = math.sqrt(x*x + z*z)
                    if r > 1e-9:
                        # cone side normal: gradient of x^2+z^2-((1-y)/2)^2
                        gx, gy, gz = 2*x, (1-y)/2.0, 2*z
                        gl = math.sqrt(gx*gx + gy*gy + gz*gz)
                        n = (gx/gl, gy/gl, gz/gl)
                        if best is None or t < best[0]:
                            best = (t, n)
    # base cap: y = -1 disk
    if abs(dy) > 1e-12:
        t = (-1.0 - oy) / dy
        if t > 1e-6:
            x, z = ox + t*dx, oz + t*dz
            if x*x + z*z <= 1.0 and (best is None or t < best[0]):
                best = (t, (0.0, -1.0, 0.0))
    return best

def render():
    img = bytearray(W * H * 3)
    tanf = math.tan(FOV / 2)
    for j in range(H):
        for i in range(W):
            u = (2*(i + 0.5)/W - 1) * tanf
            v = (1 - 2*(j + 0.5)/H) * tanf
            d = (u, v, -1.0)
            dl = math.sqrt(sum(c*c for c in d)); d = tuple(c/dl for c in d)
            hit = cone_intersect(CAM, d)
            idx = (j*W + i) * 3
            if hit is None:
                img[idx:idx+3] = bytes(BG)
            else:
                _, n = hit
                diff = max(0.0, sum(n[k]*LIGHT_DIR[k] for k in range(3)))
                r = min(1.0, AMBIENT[0] + DIFFUSE[0]*diff)
                g = min(1.0, AMBIENT[1] + DIFFUSE[1]*diff)
                b = min(1.0, AMBIENT[2] + DIFFUSE[2]*diff)
                img[idx:idx+3] = bytes((int(r*255), int(g*255), int(b*255)))
    return img

def write_png(path, img):
    raw = b""
    stride = W * 3
    for j in range(H):
        raw += b"\x00" + bytes(img[j*stride:(j+1)*stride])
    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)

if __name__ == "__main__":
    out_png = sys.argv[1] if len(sys.argv) > 1 else "cone-reference.png"
    img = render()
    write_png(out_png, img)
    # same statistics as tools/png_stats.py, on the RGB buffer
    n = W * H; cone = 0; colours = set(); lums = []
    for i in range(n):
        r, g, b = img[i*3], img[i*3+1], img[i*3+2]
        if r > 90 and r > g + 25 and g > b + 10: cone += 1
        if i % 7 == 0:
            colours.add((r << 16) | (g << 8) | b)
            lums.append((r*299 + g*587 + b*114)//1000)
    mean = sum(lums)/len(lums)
    var = sum((L-mean)**2 for L in lums)/len(lums)
    print(json.dumps({
        "file": out_png, "width": W, "height": H, "method": "analytic raycast reference",
        "cone_colour_fraction": round(cone/n, 4),
        "distinct_colours_sampled": len(colours),
        "lum_std_sampled": round(var**0.5, 2),
        "lum_min_sampled": min(lums), "lum_max_sampled": max(lums),
    }, indent=1))
