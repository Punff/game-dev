# Web Build

## Export

```bash
godot --headless --path . --export-release "Web" ../build/web/index.html
```

Output in `../build/web/` — `index.pck` is ~0.4 MB, the rest is the stock
Godot engine (`index.wasm`, ~39 MB uncompressed, ~9 MB gzipped).

## Test locally

Must be served over HTTP (`file://` won't work). On Windows, Python's plain
`http.server` sends `.js` files as `text/plain`, which breaks the audio
worklets, so register the right type:

```bash
cd ../build/web && python -c "import http.server,mimetypes; mimetypes.add_type('application/javascript','.js'); http.server.test(HandlerClass=http.server.SimpleHTTPRequestHandler, port=8060, bind='127.0.0.1')"
# open http://127.0.0.1:8060/index.html
```

Online rooms work from a local build too (they use the live room service).
To try two players, open the page in two separate browser windows side by
side: a tab hidden behind another counts as backgrounded, and if it's the
host the match stalls.

## Preset settings

| Setting | Value |
|---|---|
| Threads | single-threaded — no COOP/COEP headers needed, works on itch.io, GitHub Pages, any static host |
| GDExtension | off. The WebRTC add-on in `addons/webrtc` is desktop-only and excluded from web exports (browsers have WebRTC built in) |
| Renderer | GL Compatibility / WebGL 2 — the project uses it on desktop too, so what you see in the editor is what the browser shows |
| Loading page | dark themed via `html/head_include` |

## Hosting

- Upload the whole `build/web/` folder; entry point `index.html`.
- Enable gzip/brotli for `.wasm` and `.pck` (big load-time win).
- itch.io: "This file will be played in the browser", viewport 1280×720,
  tick "Fullscreen button".

## Web specifics handled in-game

- Settings are saved to browser storage (IndexedDB via `user://`).
- Frame pacing: browsers don't report the refresh rate, so Godot can't smooth
  frame times there. `WebPacing` measures it at startup and on a ~60 Hz display
  turns physics interpolation off so physics runs exactly one step per frame
  (smoother, about a frame less input lag). Faster displays keep interpolation.
- "Quit" is hidden; VSync option hidden (browser controls it).
- Fullscreen toggle works from the Settings menu (needs a click/keypress).
- Game auto-pauses when the tab loses focus or a controller disconnects.
- Ships silent; any sounds added to assets/sfx/ start after the first click (browser autoplay rule).
- Gamepads: browsers only expose a pad after a button is pressed on it.

## Verified

Headless Chromium (SwiftShader software GL): menu → lobby → 2 keyboard players
join/ready → countdown → gameplay, zero console errors. Same machine, same
software renderer: original build ~5 fps with 24–34 console errors per run,
this build ~10 fps with none.
