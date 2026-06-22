MSI Monitor Control — App Icon
================================

Master source: icon.svg (1024×1024 viewBox, vector)

Design
------
Dark navy squircle background, silver monitor bezel, dark screen panel,
and a pair of teal circular switch arrows overlaid on the screen.
Palette: #111E2E–#22334A background, #D0D8E4 bezel, #00D4C2–#0098A8 arrows.
Readable at 16 px; no fine detail that disappears when small.

Derived files
-------------
  icon-1024.png   — 1024×1024 RGBA PNG (preview / README / GitHub)
  icon.icns       — macOS multi-resolution icon (12 sizes, ic12 bundle)
  icon.ico        — Windows multi-resolution icon (16 / 32 / 48 / 256 px, PNG-in-ICO)
  icon.iconset/   — Intermediate .iconset directory used to build icon.icns

How to regenerate
-----------------
Requirements: macOS (sips + iconutil built-in), Python 3 + Pillow (pip3 install pillow),
optionally rsvg-convert or ImageMagick for higher-fidelity SVG rasterisation.

1. Rasterise SVG to 1024 PNG:
     qlmanage -t -s 1024 -o /tmp /path/to/assets/icon.svg
     # Output: /tmp/icon.svg.png

2. Build macOS iconset:
     SRC=/tmp/icon.svg.png
     ICONSET=assets/icon.iconset
     mkdir -p "$ICONSET"
     for size in 16 32 64 128 256 512; do
       sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png"
       double=$((size * 2))
       [ $double -le 1024 ] && sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png"
     done
     cp "$SRC" "$ICONSET/icon_512x512@2x.png"
     iconutil -c icns "$ICONSET" -o assets/icon.icns

3. Build Windows ICO (see tools/build-ico.py, or run inline Python):
     python3 -c "
     import struct, io
     from PIL import Image
     src = Image.open('/tmp/icon.svg.png').convert('RGBA')
     sizes = [16, 32, 48, 256]
     pngs = []
     for s in sizes:
         buf = io.BytesIO(); src.resize((s,s)).save(buf,'PNG'); pngs.append(buf.getvalue())
     n = len(sizes); header = struct.pack('<HHH',0,1,n)
     cur = 6+n*16; entries = b''
     for s,d in zip(sizes,pngs):
         w=s if s<256 else 0; h=s if s<256 else 0
         entries+=struct.pack('<BBBBHHII',w,h,0,0,1,32,len(d),cur); cur+=len(d)
     open('assets/icon.ico','wb').write(header+entries+b''.join(pngs))
     "

4. Copy 1024 PNG preview:
     cp /tmp/icon.svg.png assets/icon-1024.png

Verification
------------
  file assets/icon.icns   # → Mac OS X icon
  file assets/icon.ico    # → MS Windows icon resource - 4 icons
  sips -g all assets/icon.icns
