# Epochs of War

A WW2 grand strategy game (1936-1945) in the style of Hearts of Iron, built with
Godot 4 and GDScript. Play as Germany, the Soviet Union or the United Kingdom on
a simplified 20-province European map. Manage production, research, diplomacy
and divisions in real time with pause. Attacks on the five major cities (Berlin,
Moscow, Leningrad, Stalingrad, London) can zoom into a turn-based 20×20 tactical
battle where you command the units yourself.

All graphics are procedural (Godot 2D drawing). The project has no external
dependencies and no imported image assets.

The full spec is in [`v1_game_design.md`](v1_game_design.md).

## Engine version

The spec asks for Godot 4.7. This project uses **Godot 4.7.2-stable**
(official build, `Godot_v4.7.2-stable_win64`), the newest 4.7 stable release.

## How to launch

The portable Godot binary is not stored in git. Download
`Godot_v4.7.2-stable_win64.exe.zip` from
<https://github.com/godotengine/godot/releases/tag/4.7.2-stable> and extract it
into `tools/godot/` (the folder is in `.gitignore`):

```
tools/godot/Godot_v4.7.2-stable_win64.exe          (GUI launcher)
tools/godot/Godot_v4.7.2-stable_win64_console.exe  (console wrapper, used by tests)
```

**To play:**

```
tools\godot\Godot_v4.7.2-stable_win64.exe --path .
```

This opens the start screen. Choose **New Game** or **Load Game**, then pick a
nation (Germany, Soviet Union, or United Kingdom) and the game begins at
1 January 1936.

**To open in the editor:**

```
tools\godot\Godot_v4.7.2-stable_win64.exe --path . --editor
```

**First run on a fresh clone** (builds the import cache):

```
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

### Map controls

- **Left click**: select a province (click empty sea/off-map to clear)
- **Mouse wheel**: zoom towards the cursor
- **Left drag / middle drag / arrow keys / WASD**: pan

### Time controls

- **Space** or **P**: pause / resume (the game starts paused)
- **1–4**: speed 1× / 2× / 3× / 5×
- **+** / **-**: faster / slower
- Or use the PAUSE/PLAY and 1–4 buttons in the top bar

### Pause menu

Press **Escape** during play to open the pause menu (Save Game / Load Game / Resume).

## Tests

Headless tests live in `tests/`. Run the whole suite (import, smoke run of the
main scene for 120 frames, then every `tests/test_*.gd`):

```
powershell -ExecutionPolicy Bypass -File tests\run_all.ps1
```

To run a single test file:

```
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_step1_project.gd
```

**All 20 test files pass — 1,878 assertions, 0 failures.**

## Current status — build complete

All 20 steps from the design document are done. The game is playable end to end.

| Step | Feature | Status |
|---|---|---|
| 1 | Project setup | ✅ done |
| 2 | Data layer (20 provinces, 6 terrains, 3 nations, 15 techs, 3 division templates) | ✅ done |
| 3 | Strategic map rendering (province polygons, nation colours, borders, zoom/pan, click-to-select) | ✅ done |
| 4 | UI shell (top bar, info panel, 3-tab side panel, minimap) | ✅ done |
| 5 | Time system (pause, 4 speeds, date display, keyboard shortcuts) | ✅ done |
| 6 | Production (factory assignment, equipment output, resources, factory construction) | ✅ done |
| 7 | Research (15 techs in 3 branches, one at a time, progress bar, tech effects) | ✅ done |
| 8 | Military recruitment (recruit from Production tab, training queue, unit icons on map) | ✅ done |
| 9 | Division movement (select division, click destination, BFS through friendly territory, travel time, movement arrows) | ✅ done |
| 10 | Strategic combat (daily resolution, attack vs defense with terrain/entrenchment/artillery, retreat or destroy, province capture, front lines) | ✅ done |
| 11 | Supply system (capital-connected check, out-of-supply attrition, hatched overlay) | ✅ done |
| 12 | Fog of war (own territory + adjacent to own divisions visible; rest grey; reveals on move/capture) | ✅ done |
| 13 | Diplomacy (war goal fabrication 30 days, declare war, NAP, military access; scripted AI wars) | ✅ done |
| 14 | AI opponent (production priority, research order, recruitment, border positioning, 2× attack rule, auto-resolves tactical) | ✅ done |
| 15 | Tactical battle map (seeded 20×20 grid, 7 tile types, 3 objectives, deployment zones, unit placement) | ✅ done |
| 16 | Tactical unit actions (move, attack, dig in, overrun, barrage, overwatch; one action per unit per phase) | ✅ done |
| 17 | Tactical battle flow (20-turn limit, flanking +50%, morale checks/rout, victory/defeat, results feed back to strategic layer) | ✅ done |
| 18 | Save/load (JSON serialisation, pause menu, autosave every 30 in-game days) | ✅ done |
| 19 | Game flow (start screen, nation select, end conditions, victory/defeat screen with stats) | ✅ done |
| 20 | Polish (balance pass, UI cleanup, spec compliance check) | ✅ done |

See [`PROGRESS.md`](PROGRESS.md) for full architecture notes and per-step test details.

## Known gaps against the spec

These are all deliberate or minor; none block normal play.

- **Mediterranean out of supply for UK**: the Mediterranean naval zone is not
  connected to London through friendly territory, so UK divisions there always
  take attrition. Sea lanes between controlled naval zones were not added in v1.

- **Fog of war does not share vision through military access or pacts**: only the
  player's own territory and their own divisions grant sight. This is display-only;
  move orders into hidden provinces still work.

- **AI limitations (by design)**: no diplomacy AI, no factory building, no naval
  moves (UK AI stays home), ignores fog, does not pull back out-of-supply
  divisions, uses division counts (not strength) for the 2× attack rule.

- **France–UK "alliance"** is a NAP + military access, not a full alliance system.
  Sufficient for v1.

- **Movement is daily**: divisions jump province-to-province at day boundaries;
  the arrow's progress dot shows partial progress. Enemy/AI move arrows are not
  drawn.

- **End screen battles_won / divisions_lost show 0**: the stats are tracked
  correctly in `nation_state.stats` and incremented by the combat autoload, but
  `end_screen.gd` reads them via a method guard that is never satisfied. Provinces
  conquered and time played display correctly.

- **Captured provinces stay owned by the original nation** (occupation) until
  capitulation; the owner field is not transferred mid-war.
