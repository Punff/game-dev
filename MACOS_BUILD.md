# macOS Build

## Export (works from Linux/Windows/macOS)

```bash
godot --headless --path . --export-release "macOS" ../build/macos/UltimateCakumPakum.zip
```

Or in the editor: **Project → Export → macOS → Export Project**.
Output: `../build/macos/UltimateCakumPakum.zip` → `Ultimate Cakum Pakum.app`.

## Preset settings

| Setting | Value |
|---|---|
| Bundle ID | `com.divineintellect.ultimatecakumpakum` |
| Version / Short version | `1.0.0` |
| Architecture | `universal` (arm64 + x86_64) |
| Min macOS | 13.0 (Apple Silicon), 11.0 (Intel) |
| Icon | `res://assets/icon.png` (1024×1024, converted to `.icns` at export) |
| Codesign | Built-in **ad-hoc** |
| Notarization | Disabled |
| Renderer | Vulkan (MoltenVK is statically linked into the binary — no system Vulkan needed) |

## Running it on a Mac

Ad-hoc signed builds are blocked by Gatekeeper when downloaded. On the Mac:

- Right-click the app → **Open** → **Open** (once), or
- `xattr -dr com.apple.quarantine "/path/to/Ultimate Cakum Pakum.app"`

## Shipping to the public (requires an Apple Developer account)

1. On a Mac: set **Codesign** to *Xcode codesign* with a **Developer ID Application** certificate, or from Linux use *rcodesign* with a `.p12` certificate.
2. Set **Apple Team ID** in the preset.
3. Enable **Notarization** (`notarytool` on Mac / `rcodesign` elsewhere).
4. Gatekeeper then accepts the app without workarounds.

Ad-hoc builds cannot be notarized (enforced by the exporter).

## Known noise in the log

`addons/godot-jolt` declares `compatibility_maximum = 4.6`, so on Godot 4.7.x it fails
to load and prints 3 errors at startup. Harmless — the project runs on the built-in
GodotPhysics2D. Kept intentionally; remove the addon to silence it.
