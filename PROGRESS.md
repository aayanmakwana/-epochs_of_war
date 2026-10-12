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
| 4 UI shell | done | `tests/test_step4_ui.gd`: HUD under UI, root ignores mouse, panels block it; top bar position/height, date, nation, flag, manpower/oil/steel/factories values + refresh on `nation_changed`/`province_changed`/`day_passed`, 4 speed buttons mirror `speed_changed`; info panel opens on select, province fields (terrain, factories, resources, owner, garrison), garrison button -> division view (stats, orders), back button, naval zone has no buildings, occupied note + rebuild on change, close button clears map selection, off-map click hides, destroyed division falls back; 3 tabs with placeholders, `select_tab`, `clear_tab`, collapse/expand, layout; minimap bottom-right below side panel, transform round trip, whole map fits, click focuses camera, viewport rect follows zoom; injected click on minimap does not select, click on map area does; drag released over a panel ends the drag (no stuck panning); new game refreshes HUD |
| 5 Time system | done | `tests/test_step5_time.gd`: autoloads present + order, speeds 1/2/3/5, new game resets to paused speed 1 (+ `speed_changed`), paused clock frozen, pause/speed API (clamping, faster/slower, unpause flag) emits `speed_changed`, 1x = 24 h per real second, fractional hours carry over, 1:2:3:5 ratio, per-frame hour cap, hour_passed -> day_passed -> month_passed order, leap year, Simulation ordering/replace/unregister and systems run before `day_passed`, game over freezes + pauses, `time_played`, top bar buttons drive TimeManager and labels follow hour/day, real-time advance at 5x, keyboard shortcuts |
| 6 Production system | done | `tests/test_step6_production.gd`: Production autoload + registered daily system; default factory split (17 German factories -> 9/4/4); allocation API clamping (no free factories, 0..assigned+free, unknown equipment); exact one-day numbers (output, steel income/use, manpower +800, `nation_changed`); fractional progress carry-over; oil shortage stalls armor (flag, progress capped at one unit, resumes); production_mult tech; factory build: cost 50 steel, refusals (foreign, naval, occupied, no steel with reason, province cap), completion after `factory_build_days` with `factory_completed`, occupied construction paused; allocation clamped after losing a province; save round trip keeps allocation + queue; capitulated nations skipped; Production tab UI (rows, -/+ buttons, output/stockpile labels, steel balance, build buttons only for owned provinces, build spends steel, construction list, disabled build + tooltip, refresh after a day) |
| 7 Research system | done | `tests/test_step7_research.gd`: Research autoload + daily system after production; statuses (researched/available/locked) and refusal reasons (prerequisite, done, unknown, already researching, capitulated); available techs + branch progress; exact 30-day completion with `research_started`/`research_completed`/player `notify`, nothing one day early; light tanks unlocks armor; medium tanks armor attack +15%; switching keeps partial progress in `research_saved`, stop keeps progress, no progress while idle, resume; save round trip (current, progress, saved partials, researched); AI/minor nations research in parallel, capitulated skipped, no notify for AI; total war production +15%; Research tab UI (3-column grid, branch headers, tier layout, 15 buttons, Done/locked tooltips, click starts research, current tech label + progress bar + days left, per-button bar, template stats refresh, stop button) |
| 8 Military recruitment | done | `tests/test_step8_recruitment.gd`: Recruitment autoload + daily system after research; refusals (armor without light tanks, naval zone, foreign/occupied province, unknown template, manpower/equipment shortage with reason, refused recruit changes nothing); default deploy = capital, deploy list = owned+controlled land provinces; exact costs paid up front (manpower, equipment); cancel refunds; nothing one day early, division created on day 30 in the chosen province with `division_created` + player notify; lost deploy province falls back to the capital; queue save round trip; AI/minor nations train too; UI (panel in Production tab, 3 buttons with cost text, default capital, map selection of an owned province sets deploy, foreign ignored, dropdown, button recruits into chosen province, queue row cancel, disabled + reason tooltip); map unit icons (per province/owner box, count, type letters, follows new divisions) |
| 9 Division movement | done | `tests/test_step9_movement.gd`: Movement autoload + daily system after recruitment; BFS paths (adjacent, 2-hop, none into neutral/foreign/UK sea/own province, UK may enter its sea), refusal reasons (naval, not friendly, already there), refused order changes nothing; military access opens land provinces (multi-hop through access), adjacent at-war enemy province is a valid final target but not passable; travel days (infantry 4 speed, forest 6 d, urban infra 5 4 d, armor faster, artillery slower); order -> path + `division_order_changed`, ETA, 75% after 3 of 4 days, arrival on the exact day with origin + `division_moved(id, from, to)`, progress reset; save/load mid-move keeps path + progress, nothing one day early; stop; target lost -> halt + player notify; intermediate lost -> reroute to same destination; capitulated frozen; UI: garrison button selects division for orders + move hint, click on foreign province refused with notify (selection kept), click on valid province orders without changing province selection, Stop button / ETA / orders text, movement arrow points/selected/progress, right-click orders, Escape clears unit selection, unit icon click selects all player divisions there (info panel group size) + group order, province selection clears unit selection, foreign divisions not selectable for orders |
| 10 Strategic combat | done | `tests/test_step10_combat.gd`: Combat autoload + daily systems after movement, hook set; combat math (attack, artillery support +20%, mountain attack -25% / defense up, entrenchment +25%, HP strength factor, damage formula + ratio clamp); entrenchment/org/HP recovery, no entrenchment while moving; attack on Poland: battle_started on arrival, attackers wait in origin, 0-HP division destroyed, save/load mid-battle, attacker win -> capture (controller changes, owner keeps claim), province_captured, defenders without retreat destroyed, stats; undefended province captured on arrival without battle; lone artillery vs entrenched mountain defender loses and stops; Soviet defender retreats to adjacent Soviet province; stopping the attacker ends the battle; UI: no fronts at peace, Berlin-Poland front at war, battle marker, info panel BattleInfo + Bar_Battle only on the battle province |
| 11-20 | pending | |

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
                           UI (CanvasLayer) -> HUD (scripts/ui/hud.gd), see "HUD (step 4)"
scripts/map/             MapView (renders map, selection), MapCamera (zoom/pan), DrawLayer (Node2D delegating _draw)
scripts/game/            game.gd (wires camera to map, hud.setup(map_view, camera), focuses near the player's capital)
scripts/ui/              Hud, TopBar, InfoPanel, SidePanel, Minimap, FlagView (flag.gd), UIStyle (theme/colours/format)
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

### HUD (step 4)
- `Hud` (Control, full rect, `MOUSE_FILTER_IGNORE`) is `$UI/HUD` in game.tscn (`game.hud`). It builds its children in code
  and sets `theme = UIStyle.make_theme()`. Fields: `top_bar`, `info_panel`, `side_panel`, `minimap`, `map_view`.
  Every panel uses `MOUSE_FILTER_STOP`, so clicks/wheel over panels never reach the map's `_unhandled_input`.
- Layout constants are in `UIStyle` (TOP_BAR_HEIGHT 56, MARGIN 8, LEFT_PANEL_WIDTH 360, RIGHT_PANEL_WIDTH 430,
  MINIMAP_WIDTH 340). Helpers: `UIStyle.label(text, size, color)`, `section_header`, `panel_box`, `flat_box`,
  `fmt_int` (1,234), `fmt_compact` (900.0K / 2.50M). UIStyle and FlagView don't use autoloads.
- `TopBar`: flag + nation name, `date_label` (GameState.date_string()), `time_label` (hour), `pause_button`,
  `speed_buttons` (one per `rules.speeds`, 4), `resource_labels` / `resource_text(id)` for manpower, oil, steel, factories.
  Refreshes on `game_state_ready`, `day_passed`, `hour_passed` (date only), `nation_changed` (player), `province_changed`.
  **Step 5 contract:** the buttons call `/root/TimeManager` `toggle_pause()` and `set_speed(index)` if the autoload has them,
  and the bar mirrors `EventBus.speed_changed(speed_index, paused)`. The TimeManager should emit `speed_changed` after every
  change (and once at start). Without a TimeManager the buttons only change local state (starts paused, speed 0).
  Keyboard shortcuts (Space etc.) are not wired yet.
- `InfoPanel` (left): opens on `province_selected` / `division_selected`, closes on `selection_cleared` and `game_state_ready`.
  `mode` "" | "province" | "division", `current_province`, `current_division`, `content` (VBox, rebuilt).
  Province view: title/subtitle (capital / major city / naval zone), owner flag + name, "Occupied by", terrain grid,
  resources per day, buildings (factories + queued, infrastructure, not shown for naval zones), garrison buttons
  (`Division_<id>`, pressing one emits `division_selected`). Division view: stats from `TechEffects.division_stats`, HP / org
  bars, orders (path), `BackToProvince` button. `X` closes and emits `selection_cleared` (MapView drops the highlight).
  Rebuilds at most once per frame (`mark_dirty()`) on province/nation changes, day_passed, division created/moved/destroyed,
  battles and captures. `value_text(key)` reads a value row (tests). Signal `content_built(mode)` lets later steps
  add sections (e.g. step 9 move hints, step 12 hide enemy garrisons under fog).
- `SidePanel` (right, tabs "Production", "Research", "Diplomacy"): `tab_content(name)` -> VBoxContainer inside a
  ScrollContainer, holding a `Placeholder` label until `clear_tab(name)` is called. `select_tab(name)`, `current_tab_name()`,
  `set_collapsed(bool)`, signal `tab_changed(name)`. **Steps 6 / 7 / 13: `clear_tab` then fill your tab.**
- `Minimap` (bottom right): `canvas` draws the province polygons in `map_view.province_color` plus the camera's
  `visible_world_rect()`. Redraws on `view_changed`, `province_changed`, `game_state_ready`. Left click/drag ->
  `camera.focus_on`. `map_transform()`, `to_world(local)`, `to_local_point(world)`, `viewport_rect_local()`, `focus_local()`.
  It does not draw units or fog yet. If step 12 hides provinces, redraw the canvas from there.
- Step 4 changes to step 3 code: `MapView._unhandled_input` turns the event's own position into world space
  (`_event_world_pos`) instead of `get_global_mouse_position()`, so injected events (`root.push_input`) work in headless
  tests. `MapCamera._input` ends a drag on button release even when a HUD panel consumes the release.

### Time system (step 5)
- **TimeManager** (`scripts/autoload/time_manager.gd`): real time with pause, advancing in whole in-game hours.
  At speed multiplier 1 a day takes `rules.seconds_per_day_at_1x` (1 s); `speeds` = `rules.speeds` [1,2,3,5] (floats from JSON).
  One frame simulates at most `rules.max_hours_per_frame` (48) hours; fractional hours carry over.
  Per hour: `GameState.hour`/`day_index` advance -> `Simulation.run_hour()` -> `EventBus.hour_passed(hour)`.
  On a new day: `Simulation.run_day()` -> `EventBus.day_passed(day_index)` -> `month_passed(year, month)` on the 1st.
  State: `paused` (starts true), `speed_index` (0-3). API: `toggle_pause()`, `pause()`, `resume()`, `set_paused(b)`,
  `set_speed(i, unpause=false)` (clamped; does NOT unpause by default), `faster()`, `slower()`, `is_running()`,
  `hours_per_second()`, `advance_hours(n)` / `advance_days(n)` (immediate, ignore pause - use in tests/AI).
  Emits `speed_changed(index, paused)` after every change. Resets to paused speed 0 on `game_state_ready`; pauses on
  `game_over`; clock frozen while `GameState.game_over`. Adds real delta to `GameState.time_played` while active (also paused).
  Keys (`_unhandled_input`, only while a game is active): Space/P pause, 1-4 speed, +/= and - faster/slower.
- **Simulation** (`scripts/autoload/simulation.gd`): fixed-order system dispatcher. **Steps 6+ register here instead of
  connecting to day_passed** so state is updated before UI refreshes:
  `Simulation.register_daily("production", callable, order)` / `register_hourly(...)`; lower order first, ties by
  registration order, same name replaces. `unregister(name)`, `daily_systems()`, `hourly_systems()`, `hours_run`, `days_run`.
  Suggested orders: production 10, research 20, recruitment 30, movement (hourly) 10, combat (hourly) 20, AI 90, autosave 100.
- TopBar syncs from TimeManager on `_ready` (the start-up `speed_changed` fires before the HUD exists).

### Production (step 6)
- **Production** autoload (`scripts/autoload/production.gd`, after TimeManager) registers
  `Simulation.register_daily("production", run_daily, 10)`. Per day, for each non-capitulated nation in `GameData.nation_ids`
  order: (1) steel/oil income from *controlled* provinces + `colonial_income`; (2) manpower += `manpower_daily` x tech
  manpower multiplier (**manpower growth lives here; step 8 only spends it**); (3) factory construction counts down
  only in provinces the nation owns AND controls (occupied = paused), completion -> `ps.factories += 1`,
  `factory_completed(pid)`, `province_changed(pid)`; (4) equipment: `assigned x production_per_factory x production mult`
  points/day, every `cost` points = 1 unit if steel/oil in stockpile allows (equipment order infantry_equipment, armor,
  artillery consumes first). Short -> `shortages[nid][eq] = true`, progress capped at one unit. Then `nation_changed(nid)`.
- New games: `GameState.new_game` calls `Production.apply_default_allocation(nid)` for every nation
  (`rules.default_production_split` 50/25/25, remainder to infantry). Loads keep allocations exactly as saved.
  `sanitize_allocation(nid)` (removes from the last equipment type) runs in `_produce` and on `province_changed`.
- API: `set_allocation(nid, eq, n)` / `change_allocation(nid, eq, delta)` (clamped, emit `nation_changed`), `allocation`,
  `allocated_total`, `available_factories` (= `GameState.factory_count`), `free_factories`, `points_per_factory`,
  `daily_output(nid, eq)`, `daily_resource_use`, `resource_income`, `daily_net`, `manpower_growth`, `affordable_units`,
  `is_short`, `build_factory_error(nid, pid)` ("" = ok, else reason), `can_build_factory`, `build_factory` (pays
  `factory_build_cost_steel`, appends `{days_left: factory_build_days}` to `ProvinceState.factory_queue`),
  `construction_list(nid)` ({province, days_left, paused}), `buildable_provinces(nid)` (owned land provinces).
- **AI (step 14)** can call the same API for its nations; equipment stockpiles (`NationState.stockpile[eq]`) are what
  step 8 recruitment spends.
- UI: `ProductionPanel` (`scripts/ui/production_panel.gd`, `hud.production_panel`) fills the "Production" tab. Built once,
  refreshed in place at most once per frame (day_passed, nation/province changed, factory_completed, game_state_ready).
  `equip_rows[eq]` = {minus, plus, assigned, output, stock, shortage}; Shift+click = 5 factories. `resource_labels`
  (steel/oil balance), `build_buttons[pid]` (disabled with the reason as tooltip), `construction_box` (rebuilt each refresh).
  **Step 8: add recruitment below the panel's content (or as a section in it) in the same tab.**

### Research (step 7)
- **Research** autoload (`scripts/autoload/research.gd`, after Production) registers
  `Simulation.register_daily("research", run_daily, 20)`. One tech at a time per nation: each day every non-capitulated
  nation with `current_research` adds `rules.research_speed` (1.0) days to `research_progress`; at the tech's `days` the
  tech is appended to `NationState.researched`, current cleared, `research_completed(nid, tid)` + `nation_changed(nid)`
  emitted (+ `notify("Research complete: ...")` for the player). Effects need no code: `TechEffects` reads `researched`.
- Switching or stopping shelves partial progress in **`NationState.research_saved`** (tech -> days, new field, saved);
  picking that tech again resumes it.
- API: `start_research(nid, tid)` (bool; emits `research_started`), `cancel_research(nid)`, `research_error(nid, tid)`
  ("" = ok, else reason), `can_research`, `status(nid, tid)` ("researched"|"researching"|"available"|"locked"),
  `current(nid)`, `progress_days`, `progress_fraction(nid, tid="")`, `days_left(nid, tid="")`, `tech_days`, `tech_name`,
  `available_techs(nid)` (branch order, then tier), `branch_progress(nid, branch)` {done, total}, `is_researched`.
  **AI (step 14)**: call `available_techs` / `start_research` (doc order infantry > armor > doctrine).
- `GameData.techs_in_branch(branch)` returns a PackedStringArray of **ids** (not dicts).
- UI: `ResearchPanel` (`scripts/ui/research_panel.gd`, `hud.research_panel`) fills the "Research" tab: current tech
  (`current_name`, `current_bar`, `current_days`, `stop_button`), `TechGrid` (GridContainer, 3 columns = branches, header
  row then tiers), `tech_cards[tid]` = {card, button, bar} (button coloured by status, description + reason in tooltip),
  `template_labels[division]` with effective stats / lock state. Refreshed in place at most once per frame.

### Recruitment (step 8)
- **Recruitment** autoload (`scripts/autoload/recruitment.gd`, after Research) registers
  `Simulation.register_daily("recruitment", run_daily, 30)`. `recruit(nid, template, pid)` pays the template's
  `manpower` and `equipment` (from `NationState.stockpile`) **up front** and appends
  `{template, province, days_left: recruit_days}` to `NationState.recruit_queue`. All queued items train in parallel
  (-1 day/day); at 0 the division is created with `GameState.add_division` and `division_created(id)` is emitted
  (+ `notify("<Name> ready in <Province>")` for the player), then `nation_changed(nid)`.
- Deploy provinces = land provinces the nation owns AND controls (`is_valid_deploy`, `deploy_provinces`,
  `default_deploy_province` = capital else first). If the chosen province was lost, the division appears in the
  default province; with none it waits at 0 days. Capitulated nations are skipped.
- API: `recruit_error(nid, tid, pid)` ("" = ok, else reason), `can_recruit`, `cancel_recruit(nid, index)` (full refund),
  `queue(nid)` (copies + `total_days`, `progress`), `queued_count(nid, tid="")`, `affordable_count(nid, tid)`,
  `manpower_cost`, `equipment_cost`, `recruit_days`, `cost_text`, `template_name`, `is_unlocked`.
  **AI (step 14)**: `recruit(nid, "infantry", Recruitment.default_deploy_province(nid))` when `can_recruit`.
- UI: `RecruitPanel` (`scripts/ui/recruit_panel.gd`, `hud.recruit_panel`) sits below `ProductionPanel` in the
  Production tab: `manpower_label`, `deploy_option` (OptionButton) + `deploy_province` (default capital; set by
  `province_selected` when the player owns/controls the province; `set_deploy_province(pid)`), `recruit_buttons[template]`
  ("Recruit <name> (cost)", disabled with reason tooltip), `queue_box` rows `Item<i>` with `Bar` and `Cancel`.
- Map: `MapView.unit_icons()` returns `{province, owner, count, letters, rect}` - one box (UNIT_BOX 46x18 world units) per
  province and owner, centred 26 px below the anchor, letters I/A/R for the templates present, filled with the nation
  colour. `_draw_units` draws them; the Units layer refreshes on `division_created/destroyed/moved` and `province_changed`.
  **Step 9**: divisions in transit still draw in `d.province`; hit-test `rect` from `unit_icons()` for clicking units.
  **Step 12**: filter hidden provinces in `unit_icons()`/`_draw_units`.

### Movement (step 9)
- **Movement** autoload (`scripts/autoload/movement.gd`, after Recruitment) registers
  `Simulation.register_daily("movement", run_daily, 40)` (**daily**, not hourly). Each day every moving division of a
  non-capitulated nation (id order) adds `1 / hop_days(d, path[0])` to `move_progress`; at 1.0 it enters `path[0]`:
  `origin = from`, `province = next`, progress 0, entrenchment 0, `division_moved(id, from, to)`; when the path empties
  `division_order_changed(id)` fires too.
- `hop_days = rules.movement_base_days (16) / speed x terrain move_cost x (1 - rules.infrastructure_move_bonus (0.1) x (infra - 3))`,
  speed from `TechEffects.division_stats` (techs apply). Infantry: plains/infra 3 = 4 days, forest 6, mountain 8.
- Passable (`is_passable(nid, pid)`): controller == nid, or land province whose controller is in `NationState.military_access`.
  Naval zones only if the nation controls them. `is_hostile(nid, pid)`: land province controlled by a nation at war with nid.
  `find_path(nid, from, to)` = BFS (fewest provinces) through passable provinces; the **final** target may be hostile
  (must be adjacent to the last friendly step). Returns `Array[String]` without `from` (empty = no route).
- API: `order_move(div_id, target)` (bool; keeps progress if the next hop is unchanged; emits `division_order_changed`),
  `order_move_group(ids, target)` (count), `move_error(div_id, target)` ("" = ok, else reason), `can_move`, `stop(div_id)`,
  `hop_days(d, pid)`, `eta_days(d)`, `division_speed(d)`.
- If the next province becomes impassable the path is recomputed to the same destination; with no route the division
  halts (notify "Division #N halted ..." for the player).
- **Step 10 hook:** `Movement.hostile_entry: Callable` - if valid it is called `(division, province) -> bool` when a division
  reaches full progress towards a hostile province; return false to hold it at progress 1.0 (battle running), true to let
  it enter. Without the hook (step 9) divisions simply enter. Combat should start there (or on `division_order_changed`).
- New EventBus signals: `division_order_changed(division_id)`, `divisions_selected(division_ids: Array)` (empty = clear).
- Map (`MapView`): `selected_divisions: Array[int]` (player's only). Set by `division_selected` (garrison button; foreign ->
  cleared), `select_divisions(ids)` (emits `divisions_selected`), or clicking a player unit icon (`unit_icon_at(world_pos)`;
  selects the province AND all player divisions in it). With divisions selected, `click_at` on another province or a
  right-click calls `order_selected_move(pid)` (refusal reason -> `notify`, selection kept) and does not change the province
  selection. `select_province`, `clear_selection`, `selection_cleared`, `divisions_selected([])`, Escape clear it.
  `move_arrows()` -> `{division, points, progress, selected}` for the player's moving divisions; `_draw_units` draws arrows
  (yellow, progress dot on the first leg), a white preview path to the hovered province, and a yellow frame around the
  selected icon. `unit_anchor(pid)` = icon centre.
- InfoPanel division view: `Eta` label ("Arrives in N days"), `Bar_Move`, `MoveHint` (player divisions, with group size
  `group_size`), `StopButton` while moving; back button emits `divisions_selected([])`. Rebuilds on `division_order_changed`.

### Combat (step 10)
- **Combat** autoload (`scripts/autoload/combat.gd`, after Movement) sets `Movement.hostile_entry` and registers
  `Simulation.register_daily("combat", run_daily, 45)` and `("combat_recovery", run_recovery, 50)`.
- A division reaching full progress towards a hostile province: no enemy divisions there -> it enters and the province is
  captured on `division_moved`; otherwise it starts/joins the battle and is held at progress 1.0 in its own province.
- Battles live in **`GameState.battles`** (pid -> `{province, attacker, defender, attackers: [ids], days, start_day}`), saved in
  `to_dict()` under `"battles"`. Defenders are recomputed each tick (divisions in the province owned by nations at war with
  the attacker); attackers = listed ids still having `path[0] == pid`.
- Daily tick: damage = `combat_damage_scale` x attack x clamp(attack / enemy defense, `combat_ratio_min`, `combat_ratio_max`),
  split evenly; each point costs `combat_org_per_damage` org and `combat_hp_per_damage` HP. Attack/defense summed over
  divisions x `strength(d)` (1 - `combat_hp_strength_weight` x lost HP fraction); attacker attack x (1 + artillery support) x
  (1 + terrain attack_modifier); defender defense x (1 + terrain defense_bonus + entrenchment x `entrenchment_defense_bonus`).
  0 HP -> destroyed; defender at 0 org -> retreats to an adjacent passable province (prefers no battle), destroyed if none;
  attacker at 0 org -> `Movement.stop`. No defenders -> attackers enter via `Movement.enter_province` (new helper) and the
  province is captured; no attackers -> defender holds.
- Capture changes **controller only** (owner keeps its claim, shown as occupied); stats `provinces_conquered`,
  `battles_won/lost`, `divisions_lost` updated.
- Recovery: entrenchment +`entrenchment_per_day` for non-moving divisions (max 1); out of battle org +`org_recovery_per_day`
  x max, HP +`hp_recovery_per_day` x max in own-controlled provinces. **Step 11** attrition should coordinate with this.
- API: `has_battle(pid)`, `battle_at(pid)`, `attackers(pid)`, `defenders(pid, attacker_nid)`, `is_in_battle(d)`,
  `powers(pid, atk, dfs)` (typed `Array[DivisionState]`), `damage(attack, defense)`, `strength(d)`, `balance(pid)` (attacker
  org share 0..1), `capture(pid, nid)`, `retreat(d)`, `destroy(d)`.
- Signals emitted: `battle_started(pid)`, `battle_ended(pid, attacker_won)`, `province_captured(pid, new, old)`,
  `province_changed`, `division_destroyed`, `division_moved` (entry/retreat), `notify` for the player.
- Map: `_draw_fronts` draws red front lines (`front_borders()` = border keys between at-war controllers) and a red outline
  around battle provinces; `_draw_units` draws a crossed-swords marker (`battle_markers()`). InfoPanel province view has a
  "Battle" section (`BattleInfo` label, `Bar_Battle`).
- **Steps 15-17**: major-city battles currently auto-resolve; hook the tactical prompt where `_on_hostile_entry` starts a battle
  and add a result-applying API. **Step 13/19**: capital capture does not yet cause capitulation.

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
- The Fog map layer is intentionally empty until step 12 (Units drawn since step 8, Fronts since step 10).
- Combat balance (rules.json combat_* keys) is first-pass; lone divisions attacking entrenched defenders usually lose. Step 20 may tune.
- Captured provinces stay owned by the original nation (occupation) until capitulation is implemented.
- Movement is daily (as specified for step 9), so divisions jump province to province at day boundaries; the arrow's
  progress dot shows partial progress. Enemy/AI move orders are not drawn.
- Headless test windows are smaller than the 1920x1080 viewport, so tests call `MapView._unhandled_input(ev)` directly
  for clicks near the screen edge instead of `root.push_input`.
- The Diplomacy tab is a placeholder until step 13 (Production filled in step 6, Research in step 7). AI nations do not pick research until step 14. Speed buttons and the clock work since step 5.
- Production balance numbers (equipment costs, default split) are first-pass; step 20 balance pass may tune them.
- Minor nations run the same economy with their default split (no AI changes until step 14).
- Tests that simulate clicks should use `root.push_input` with the event `position` set. Headless doesn't move the OS cursor,
  so `get_global_mouse_position()` is stale there.
