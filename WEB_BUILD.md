# Web Build

## Export (works from Linux/Windows/macOS)

```bash
godot --headless --path . --export-release "Web" ../build/web/index.html
```

Or in the editor: **Project → Export → Web → Export Project**.
Output: `../build/web/` (9 files, ~48 MB).

## Test locally

The build must be served over HTTP (WASM + `.pck` are fetched, `file://` will not work):

```bash
cd ../build/web && python3 -m http.server 8060 --bind 127.0.0.1
# open http://127.0.0.1:8060/index.html
```

## Preset settings

| Setting | Value |
|---|---|
| Threads | **single-threaded** (no COOP/COEP headers needed → works on itch.io, GitHub Pages, any static host) |
| GDExtension support | off |
| Texture compression | S3TC/BPTC (desktop browsers); ETC2/ASTC off — this is a keyboard/gamepad game, desktop only |
| Renderer | project is Forward+, the web build runs it on **Compatibility / WebGL 2.0** automatically (no action needed) |

## Hosting

- Upload the whole `build/web/` folder as-is; entry point `index.html`.
- Serve `.wasm` and `.pck` with `Content-Type: application/octet-stream` and gzip/brotli
  enabled — `index.wasm` is ~39 MB uncompressed, compression cuts load time a lot.
- itch.io: enable "This file will be played in the browser" on `index.html`.

## Verified

Booted in headless Chrome 155: main menu → lobby (join/ready) → gameplay scene with
map generation, lava, HUD, particles. Console shows only the two known issues below.

## Known console noise

1. **godot-jolt** — `compatibility_maximum = 4.6`, prints 3 errors at startup on Godot
   4.7.x (kept intentionally; no wasm32 library exists, extension simply doesn't load).
2. **`foreground_layer.gd:63`** — `draw_colored_polygon` fails triangulation every frame
   (`ERROR: Invalid polygon data, triangulation failed.`). Pre-existing, reproduces on
   desktop too: the cliff baseline is `_vp.y + 30` but the parallax offset
   `by = _vp.y - cam_pos.y * 0.7` pushes the cliff points below it once the camera
   rises ~130 px, making the polygon self-intersect.
   Fix: draw the bottom edge below the lowest cliff point instead of a fixed
   `_vp.y + 30`, e.g.
   `var base_y: float = _vp.y + 30; for pt in poly: base_y = max(base_y, pt.y + 1)`
   (and use `base_y` for both bottom vertices).
