# Build progress

Engine: **Godot 4.7.2-stable** (portable, `tools/godot/`, not in git).
Console binary for tests: `tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Run all tests: `powershell -ExecutionPolicy Bypass -File tests\run_all.ps1`
(imports, smoke-runs the main scene for 120 frames scanning for errors, then runs every `tests/test_*.gd`).

## Steps

| Step | Status | Test |
|---|---|---|
| 1 Project setup | done | `tests/test_step1_project.gd`: project settings (name, 1920x1080, windowed, main scene, config/features = engine version), folders, EventBus autoload, main scene instantiates |
| 2 Data layer | done | `tests/test_step2_data.gd`: 20 provinces in doc order with all fields, 6 terrains, 5 major cities, 3 playable nations + capitals, map geometry (1 loop per province, symmetric adjacency, anchors inside, connected graph, expected/forbidden adjacencies, determinism), 3 templates, 3 equipment, 15 techs (5/branch, 30-90 days, prerequisite chain), tech effects, calendar, GameState new game, JSON save-dict round trip |
| 3 Strategic map rendering | done | `tests/test_step3_map.gd`: game scene loads, 20 province Polygon2D fills + labels, all 7 layers exist, fills use nation colour (German != Soviet, naval blue), border/coastline segments exist, recolour on `province_changed` after controller change, clicking every anchor selects that province and emits `province_selected`, off-map click clears and emits `selection_cleared`, no holes between polygons, zoom clamped min/max, pan moves + clamped to bounds, `focus_on`, zoom-towards-cursor keeps world point fixed, `build()` rebuild leaves no stale layers |
| 4 UI shell | pending | |
| 5 Time system | pending | |
| 6-20 | pending | |

## Architecture

### File layout
```
project.godot            autoloads, 1920x1080 window settings, GL Compatibility renderer
data/*.json              all static game data (see below)
scenes/main.tscn         root; scripts/main.gd swaps "screens" (change_screen). Until step 19 it calls
                         GameState.new_game(nation) and boots straight into the game screen
                         (nation from `-- --nation=germany|ussr|uk`, default germany)
scenes/game/game.tscn    in-game screen: Game (scripts/game/game.gd)
                           World (Node2D) -> MapView (scripts/map/map_view.gd), MapCamera (scripts/map/map_camera.gd)
                           UI (CanvasLayer) -> empty; step 4 puts top bar / panels / minimap here
scripts/map/             MapView (renders map, selection), MapCamera (zoom/pan), DrawLayer (Node2D delegating _draw)
scripts/game/            game.gd (wires camera to map, focuses near the player's capital)
scripts/autoload/        EventBus, GameData, GameState (+ TimeManager, Simulation from step 5)
scripts/core/            pure helpers: map_geometry.gd (MapGeometry), game_date.gd (GameDate), tech_effects.gd (TechEffects)
scripts/state/           ProvinceState, NationState, DivisionState (runtime records with to_dict/from_dict)
tests/                   test_base.gd harness, test_stepN_*.gd, run_all.ps1, logs/ (ignored),
                         screenshot.gd (dev helper, not a test - renders main scene to PNG in a real window:
                         `--path . -s res://tests/screenshot.gd -- --out=C:/tmp/shot.png [--select=berlin] [--days=40]`)
```

### Running the tests
- Everything: `powershell -ExecutionPolicy Bypass -File tests\run_all.ps1` (exit 0 = all passed).
  Optional `-Filter step3` to run only matching test files.
- One test: `tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://tests/test_step3_map.gd`
  (prints `RESULT: PASS` and `--- N passed, M failed ---`).
- Project load only: `tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --quit-after 120`.
- New tests: `extends "res://tests/test_base.gd"`, implement `run_tests()` (may `await process_frame`),
  use `check(cond, msg)` / `check_eq(a, b, msg)` and `autoload("Name")`.

### Strategic map (step 3)
- `MapView` (Node2D) builds child layers from `GameData.geometry`, bottom to top:
  `Fills` (one Polygon2D per province outline, `fill_nodes[pid]`), `Borders`, `Fronts`, `Highlight`, `Units`,
  `Labels` (Label per province, `label_nodes[pid]`), `Fog`. Every layer except Fills/Labels is a `DrawLayer`
  whose `_draw` calls `MapView._draw_<layer>(canvas)`. **Fronts (step 10), Units (step 8) and Fog (step 12) are empty
  stubs**: fill in `_draw_fronts/_draw_units/_draw_fog` and call `refresh_layer("<Name>")` when data changes.
- Colour: `province_color(pid)` = controller's nation colour blended 18% with terrain colour (naval zones: terrain
  colour with 12% owner tint). Uses `GameState` controller when a game is active, else 1936 owner.
- Borders: province borders thin, nation (different controller) borders thick, coastlines blue-black.
  Widths use `px(pixels)` so they stay constant on screen at any zoom. Capitals get a gold star, major cities a dot.
- Listens to `EventBus.province_changed` (recolour + borders), `game_state_ready` (refresh_all), `selection_cleared`.
- API: `province_at(world_pos)`, `click_at(world_pos)`, `select_province(pid)`, `clear_selection()`,
  `set_hovered(pid)`, `refresh_all()`, `refresh_layer(name)`, `selected_province`, `hovered_province`.
- Input (`_unhandled_input`, so UI Controls in step 4 must consume their own clicks / use MOUSE_FILTER_STOP):
  left release without drag = select (emits `province_selected` / `selection_cleared`), mouse motion = hover
  (`province_hovered`, "" when none), right press on a province = `province_right_clicked` (for move orders, step 9).
- `MapCamera` (Camera2D): wheel zoom towards cursor (0.45-3.0), left/middle drag or arrows/WASD to pan, clamped to
  map bounds +100. API: `setup(bounds)`, `zoom_level()`, `set_zoom_level(z, screen_anchor=null)`, `pan_by(world_delta)`,
  `focus_on(world_pos)`, `visible_world_rect()` (for the minimap viewport box), `was_drag()`; signal `view_changed`.

### Autoloads (order matters: later ones may use earlier ones)
1. **EventBus** (`scripts/autoload/event_bus.gd`): signals only. All signals for later steps are already declared:
   `game_state_ready`, `game_over(result)`, `hour_passed(hour)`, `day_passed(day_index)`, `month_passed(year, month)`,
   `speed_changed(speed_index, paused)`, `province_selected(id)`, `province_hovered(id)`,
   `province_right_clicked(id)` (added in step 3), `selection_cleared`,
   `division_selected(id:int)`, `province_changed(id)`, `nation_changed(id)`, `factory_completed(province)`,
   `research_started(nation, tech)`, `research_completed(nation, tech)`, `division_created(id)`,
   `division_moved(id, from, to)`, `division_destroyed(id)`, `battle_started(province)`, `battle_ended(province, attacker_won)`,
   `province_captured(province, new_controller, old_controller)`, `war_declared(attacker, defender)`,
   `pact_signed(a, b)`, `military_access_granted(host, guest)`, `nation_capitulated(nation, conqueror)`,
   `tactical_battle_requested(province)`, `tactical_battle_finished(province, attacker_won)`, `notify(text)`.
2. **GameData** (`scripts/autoload/game_data.gd`): read-only definitions loaded from `data/*.json` at startup.
   Dictionaries keyed by id: `terrain`, `provinces`, `nations`, `divisions`, `equipment`, `techs`, plus ordered id lists
   (`province_ids` is the design-doc order), `tactical`, `rules`, `map_def`, `geometry` (MapGeometry), `errors`.
   Helpers: `province(id)`, `nation(id)`, `terrain_of(pid)`, `province_name`, `nation_name`, `nation_color`, `is_naval`,
   `is_major_city`, `is_capital`, `adjacent(pid)`, `are_adjacent(a,b)`, `playable_nations()`, `major_cities()`,
   `techs_in_branch(branch)`, `rule(key, default)`. JSON numbers are floats: wrap with `int()`.
3. **GameState** (`scripts/autoload/game_state.gd`): the entire mutable world. `new_game(player_id)`, `load_from_dict(d)`,
   `to_dict()` (save format, version 1), `add_division(template, owner, province)`, `remove_division(id)`,
   queries `province(id)`, `nation(id)`, `player()`, `division(id)`, `controlled_provinces(nid)`, `owned_provinces(nid)`,
   `factory_count(nid)` (sum over controlled provinces), `divisions_in(pid)`, `divisions_of(nid)`, `date()`, `date_string()`.
   Clock: `day_index` (days since 1 Jan 1936) + `hour`. Emits `EventBus.game_state_ready` after new game / load.

### Data files
- `map.json`: 40x23 character grid + legend (char -> province id). `.` = sea/off-map. Outlines, adjacency, anchors,
  borders are *derived* (MapGeometry) - edit the grid to change the map. Adjacency is 4-neighbour cell contact, so it
  is always consistent with what is drawn. Diagonal-only contacts are rejected by validation.
- `provinces.json`: id, name, terrain, owner (1936), major_city, infrastructure, factories, resources {steel, oil, food}/day.
- `nations.json`: 9 nations (germany, ussr, uk playable; france, poland, austria, czechoslovakia, hungary, romania minors).
  color, capital, flag {layout: horizontal|vertical|solid|cross|triangle, colors, emblem}, manpower, manpower_daily,
  stockpile, colonial_income (UK), starting_techs, starting_divisions (spawned by `GameState.new_game`), description.
  Both naval zones are owned by the UK.
- `divisions.json`: infantry/armor/artillery: attack, defense, speed, organization, hp, manpower, equipment cost,
  recruit_days, required_tech (armor needs light_tanks), support_attack_bonus (artillery), tactical_units.
- `equipment.json`: cost (production points/unit) and resources per unit (steel, oil).
- `techs.json`: 15 techs, `requires` = previous tier. Effect types: division_stat, unlock_division, production_mult,
  manpower_growth_mult, support_bonus. Apply via `TechEffects` (computed from `NationState.researched`, no hidden state).
- `tactical.json`: tile types, tactical unit stats from the doc, turn limit, city seeds.
- `rules.json`: global constants (speeds, seconds_per_day_at_1x, production_per_factory, factory_build_days,
  autosave_interval_days, attrition ...).

### State records (`scripts/state/`)
- `ProvinceState`: id, owner, controller, factories, infrastructure, factory_queue.
- `NationState`: manpower, stockpile (infantry_equipment, armor, artillery, oil, steel), factory_allocation,
  production_progress, researched, current_research, research_progress (days), recruit_queue, at_war_with,
  non_aggression, military_access, war_goals {target: days_left}, capitulated, stats.
- `DivisionState`: id, template, owner, province, hp, organization, path (next province first), move_progress,
  entrenchment, origin.
All have `to_dict()` / `static from_dict()`; add new fields to both when extending.

## Gotchas
- **Tests and autoload names**: a `-s` test script is compiled before autoload globals are registered. A test must not
  statically reference a `class_name` script that itself uses `GameData`/`GameState`/`EventBus` identifiers
  (e.g. `TechEffects`). Load such scripts at runtime: `var TE: GDScript = load("res://scripts/core/tech_effects.gd")`
  and use `autoload("GameData")` from test_base for singletons. Pure classes (MapGeometry, GameDate, state records)
  are fine to use directly. Don't use `:=` on results of calls through a GDScript variable (type is Variant).
- `tests/run_all.ps1` treats any `SCRIPT ERROR`, `Parse Error` or `ERROR:` in the smoke run as a failure.
- Fresh clone: run `--headless --import` once (run_all.ps1 does it) so `class_name` classes are registered.
- Git identity on this machine is `alerts-source <alerts@dealscope-ai.com>` (global config, left unchanged).

## Known issues
- No functional bugs known.
- Git prints "CRLF will be replaced by LF" warnings on commit (.gitattributes normalises line endings); harmless.
- The Fronts / Units / Fog map layers are intentionally empty until steps 10 / 8 / 12.
- The game screen has no HUD yet (step 4); the UI CanvasLayer in game.tscn is empty.
