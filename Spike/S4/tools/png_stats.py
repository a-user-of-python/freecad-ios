#!/usr/bin/env python3
"""Pure-stdlib PNG statistics: size, mean RGB, luminance spread,
distinct-colour estimate, and the fraction of 'cone-coloured' pixels
(orange: R high, R>G>B, warm hue) vs 'background' pixels (dark blue).
Used on simulator screenshots and reference renders so both sides of a
comparison are measured by the same code."""
import json, struct, sys, zlib

def decode_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8; w = h = None; bitdepth = ctype = None; idat = b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]; typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]; pos += 12 + ln
        if typ == b"IHDR":
            w, h, bitdepth, ctype = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
    assert bitdepth == 8 and ctype in (2, 6), f"unsupported png: depth={bitdepth} type={ctype}"
    ch = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * ch
    out = bytearray(w * h * ch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        filt = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if filt == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 0xff
        elif filt == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 0xff
        elif filt == 3:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xff
        elif filt == 4:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                b = prev[i]
                c = prev[i-ch] if i >= ch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xff
        out[y*stride:(y+1)*stride] = line
        prev = line
    return w, h, ch, bytes(out)

def stats(path):
    w, h, ch, px = decode_png(path)
    n = w * h
    sr = sg = sb = 0.0; cone = 0; bg = 0; lums = []
    colours = set()
    for i in range(0, n):
        o = i * ch
        r, g, b = px[o], px[o+1], px[o+2]
        sr += r; sg += g; sb += b
        if r > 90 and r > g + 25 and g > b + 10:
            cone += 1
        if b > r + 15 and r < 90 and g < 90:
            bg += 1
        if i % 7 == 0:
            colours.add((r << 16) | (g << 8) | b)
            lums.append((r*299 + g*587 + b*114)//1000)
    mean = sum(lums)/len(lums)
    var = sum((L-mean)**2 for L in lums)/len(lums)
    return {
        "file": path, "width": w, "height": h,
        "mean_rgb": [round(sr/n, 1), round(sg/n, 1), round(sb/n, 1)],
        "cone_colour_fraction": round(cone/n, 4),
        "dark_blue_fraction": round(bg/n, 4),
        "distinct_colours_sampled": len(colours),
        "lum_std_sampled": round(var**0.5, 2),
        "lum_min_sampled": min(lums), "lum_max_sampled": max(lums),
    }

if __name__ == "__main__":
    print(json.dumps(stats(sys.argv[1]), indent=1))
