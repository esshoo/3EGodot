# 3E USDZ Exporter — R1

Standalone Godot editor addon prototype for direct Godot Scene -> USDZ export.
It does **not** use glTF as an intermediate format.

## R1 scope

- Pure GDScript editor addon (no GDExtension/OpenUSD dependency).
- Adds `Scene > Export As... > USDZ Scene...`.
- Desktop/editor builds save `.usdz` with a file dialog.
- Web editor builds download the generated `PackedByteArray` through `JavaScriptBridge.download_buffer()`.
- Writes a USDA default layer directly from the edited scene.
- Exports `Node3D` hierarchy/local transforms.
- Exports triangle `Mesh` surfaces with positions, indices, normals and UV0.
- Reverses Godot's clockwise triangle winding to USD right-handed winding.
- Writes USDZ itself as an uncompressed ZIP with 64-byte-aligned file payloads.

Not implemented in R1: materials, textures, cameras, lights, skeletons, blend shapes, animations, MultiMesh, non-triangle primitives, USDZ/ARKit validation metadata.

## Test from the terminal

From the root of a built Godot source checkout on Windows:

```powershell
.\bin\godot.windows.editor.x86_64.exe --headless --path .\misc\3e_usdz_exporter --script res://tests/test_smoke.gd
```

Or with a Godot executable already on PATH:

```powershell
godot --headless --path .\misc\3e_usdz_exporter --script res://tests/test_smoke.gd
```

Expected output contains:

```text
3E USDZ smoke test PASS
```

## Interactive desktop test

```powershell
.\bin\godot.windows.editor.x86_64.exe --editor --path .\misc\3e_usdz_exporter
```

Open `main.tscn`, then choose:

`Scene > Export As... > USDZ Scene...`

## Web editor test

Open this test project in a Web editor build and use the same menu item. On Web, the addon skips the filesystem save dialog and invokes the browser download directly.

## External validation (recommended when OpenUSD tools are available)

```powershell
usdchecker path\to\scene.usdz
usdchecker --arkit path\to\scene.usdz
```

R1 is intentionally a small proof of architecture. Materials/textures and broader USD schemas should be added only after Desktop + Web menu/export/download behavior is verified.
