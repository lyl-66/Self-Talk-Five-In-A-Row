---
name: godot
description: This machine's Godot 4.7 setup for project AI-tset — engine path, headless/CLI commands, and project conventions
whenToUse: When working on the Godot project at C:\godot\ai-tset — editing scenes, GDScript, or running/exporting the project
---

# Godot environment on this machine

Engine (verified 4.7.2.stable.official):

- Console build: `C:\Godot_v4.7.2-stable_win64_console.exe` — use this one for anything where you need stdout/stderr
- GUI build: `C:\Godot_v4.7.2-stable_win64.exe` — same engine, no console output

Project: `C:\godot\ai-tset` (`config/name="AI-tset"`), Godot 4.7, Forward Plus renderer,
`rendering_device/driver.windows="d3d12"`, 3D physics is Jolt.

## Running from the shell

Always pass `--path` so the working directory does not matter:

```bash
# reimport assets / validate the project, then exit
"C:/Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:/godot/ai-tset" --quit

# run a one-off script (extends SceneTree or MainLoop)
"C:/Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:/godot/ai-tset" --script res://tools/check.gd

# run the project for a bounded time
"C:/Godot_v4.7.2-stable_win64_console.exe" --path "C:/godot/ai-tset" --quit-after 300
```

`--headless` is right for logic/CI-style runs: no window, no GPU, fast. It uses the dummy
rendering driver, so `_draw()` output is never produced and screenshots come out blank.

## Seeing the actual picture (verified 2025, engine 4.7.2, RTX 4060 / D3D12)

Contrary to earlier notes here, this machine **can** open a real window from the agent shell —
a non-headless run starts, renders on the GPU and quits cleanly:

```bash
"C:/Godot_v4.7.2-stable_win64_console.exe" --path "C:/godot/ai-tset" --quit-after 120
# -> D3D12 12_0 - Forward+ - Using Device #0: NVIDIA ... , exits in ~2s
```

So visual work can be verified instead of guessed. Pattern: a throwaway `SceneTree` script that
adds the scene plus a driver node, then saves frames to PNG and reads them back:

```gdscript
# tools/shot_driver.gd  (Node added under root by tools/shot.gd)
extends Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	await RenderingServer.frame_post_draw          # frame must be drawn first
	var image := get_viewport().get_texture().get_image()
	image.save_png("res://shots/board.png")
	get_tree().quit()
```

Then read `C:/godot/ai-tset/shots/board.png` with the image-reading tool and actually look at it.
`ReadMediaFile`'s `region` parameter gives full-resolution crops for fine detail (fonts, edges).

To drive the game and check behaviour through the *real* input path, synthesise events —
`Input.parse_input_event()` with `InputEventMouseButton` / `InputEventMouseMotion`, position in
viewport coordinates, `Input.use_accumulated_input = false` plus `Input.flush_buffered_events()`.

Caveats: the window is visible on the user's desktop for the duration of the run (keep it short,
a few seconds); a script that fails to parse leaves the window open until the shell timeout kills
it — pass an explicit `timeout`, and always delete the throwaway `tools/` and `shots/` afterwards.

If the project has no main scene, Godot exits with
`Can't run project: no main scene defined in the project`. That is a project state error, not an
engine problem — set `application/run/main_scene` in `project.godot` first.

## Via Godot MCP

If the `godot` MCP server is connected, its tools are named `mcp__godot__<tool>`:
`run_project`, `stop_project`, `get_debug_output`, `get_godot_version`, `list_projects`,
`get_project_info`, `create_scene`, `add_node`, `load_sprite`, `save_scene`, `export_mesh_library`,
`launch_editor`, plus the 4.4+ UID tools `get_uid` / `update_project_uids`.

Prefer `run_project` + `get_debug_output` over hand-rolled shell runs when you need the debug
output back as structured text.

## Conventions

GDScript only — do not add C# or GDExtension without asking. Files are `snake_case.gd`; the scene
that owns a script is `snake_case.tscn`. Type annotate signal handlers and exported variables
(`@export var speed: float = 100.0`).
