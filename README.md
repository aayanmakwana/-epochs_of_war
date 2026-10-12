# Epochs of War

A WW2 grand strategy game (1936-1945) in the style of Hearts of Iron, built with
Godot 4 and GDScript. Play as Germany, the Soviet Union or the United Kingdom on
a simplified 20-province European map. Manage production, research, diplomacy
and divisions in real time with pause. Attacks on the five major cities (Berlin,
Moscow, Leningrad, Stalingrad, London) can zoom into a turn-based 20x20 tactical
battle where you command the units yourself.

All graphics are procedural (Godot 2D drawing). The project has no external
dependencies and no imported image assets.

The full spec is in [`v1_game_design.md`](v1_game_design.md).

## Engine version

The spec asks for Godot 4.7. This project uses **Godot 4.7.2-stable**
(official build, `Godot_v4.7.2-stable_win64`), the newest 4.7 stable release.

## How to run

The portable Godot binary is not stored in git. Download
`Godot_v4.7.2-stable_win64.exe.zip` from
<https://github.com/godotengine/godot/releases/tag/4.7.2-stable> and extract it
into `tools/godot/` (the folder is in `.gitignore`):

```
tools/godot/Godot_v4.7.2-stable_win64.exe          (GUI)
tools/godot/Godot_v4.7.2-stable_win64_console.exe  (console wrapper, for logs/tests)
```

From the project root:

```
# First run on a fresh clone: build the import cache
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import

# Play
tools\godot\Godot_v4.7.2-stable_win64.exe --path .

# Play as another nation (until the start screen exists): germany | ussr | uk
tools\godot\Godot_v4.7.2-stable_win64.exe --path . -- --nation=ussr

# Open in the editor
tools\godot\Godot_v4.7.2-stable_win64.exe --path . --editor
```

### Map controls

- Left click: select a province (click empty sea/off-map to clear)
- Mouse wheel: zoom towards the cursor
- Left or middle drag, arrow keys or WASD: pan

## Tests

Headless tests live in `tests/`. Run the whole suite (import, a smoke run of the
main scene, and every `tests/test_*.gd`):

```
powershell -ExecutionPolicy Bypass -File tests\run_all.ps1
```

To run a single test:

```
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_step1_project.gd
```

## Development status

The build follows the 20-step Build Order in the design document.

| Step | Feature | Status |
|---|---|---|
| 1 | Project setup | done |
| 2 | Data layer | done |
| 3 | Strategic map rendering | done |
| 4 | UI shell (top bar, info panel, tabbed side panel, minimap) | done |
| 5 | Time system | pending |
| 6-20 | Production ... polish | pending |

See [`PROGRESS.md`](PROGRESS.md) for details and architecture notes.
