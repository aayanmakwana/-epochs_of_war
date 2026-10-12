class_name TacticalView
extends Control
## Tactical battle screen (step 15): replaces the strategic view with the city
## grid. Layout per the design doc: grid in the centre, unit list on the left,
## action buttons at the bottom, turn counter top-right; tile info + legend on
## the right.
##
## Step 15 covers the map and deployment: open(province) builds the TacticalMap
## for the city, splits every division in the battle into its 3 tactical units
## and auto-deploys both sides. The player rearranges their units inside their
## deploy zone: pick a unit (list or grid), click a highlighted tile (an own unit
## there swaps). Action buttons are placeholders until step 16. "Return to map"
## emits `closed` (the strategic battle keeps auto-resolving until step 17).
##
## Opening pauses the strategic clock (TimeManager.pause()).

signal closed(province_id: String)
signal unit_selected(unit_id: int)

const TOP_H := 56
const BOTTOM_H := 72
const LEFT_W := 340
const RIGHT_W := 300
const PAD := 10
## Bottom action bar (step 16). Ability buttons are enabled only for the unit type
## that has the ability (Dig in = infantry, Overrun = armor, Barrage = artillery).
const ACTIONS: PackedStringArray = ["Move", "Attack", "Dig in", "Overrun", "Barrage", "Overwatch", "End phase"]
const LOG_LINES := 8

var province: String = ""
var map: TacticalMap
var deployment: TacticalDeployment
var player_side: String = "attacker"
var phase: String = "deployment"
var turn: int = 1
var turn_limit: int = 20
var selected_unit: int = -1

var grid: TacticalGrid
var title_label: Label
var phase_label: Label
var turn_label: Label
var unit_list: VBoxContainer
var unit_buttons: Dictionary = {}   # unit id -> Button
var reserve_label: Label
var tile_info: Label
var hint_label: Label
var action_buttons: Dictionary = {} # action name -> Button
var auto_deploy_button: Button
var withdraw_button: Button
var return_button: Button
var start_button: Button
var log_label: Label
## Battle state once the deployment ends (step 16), else null.
var battle: TacticalBattle
## What a grid click on a tile does for the selected unit: move | attack | overrun | barrage.
var action_mode: String = "move"

var _built := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIStyle.make_theme()
	_build_ui()


# --- Opening -------------------------------------------------------------------

## Open the battle for [param pid] from the strategic state: the running
## Combat battle there if any (its attackers vs the defenders), otherwise the
## divisions in the province defend against the player.
func open(pid: String) -> void:
	var tm := get_node_or_null("/root/TimeManager")
	if tm:
		tm.pause()
	var combat := get_node_or_null("/root/Combat")
	var attacker := ""
	var defender: String = GameState.province(pid).controller if GameState.province(pid) else ""
	var atk: Array = []
	var dfs: Array = []
	if combat and combat.has_battle(pid):
		var b: Dictionary = combat.battle_at(pid)
		attacker = b.attacker
		defender = b.defender
		atk = combat.attackers(pid)
		dfs = combat.defenders(pid, attacker)
	else:
		attacker = GameState.player_nation if GameState.player_nation != defender else ""
		for d in GameState.divisions_in(pid):
			if d.owner == defender:
				dfs.append(d)
	open_with(pid, attacker, defender, atk, dfs)


## Open with explicit forces (Arrays of DivisionState).
func open_with(pid: String, attacker: String, defender: String, attacker_divs: Array, defender_divs: Array) -> void:
	if not _built:
		_build_ui()
	province = pid
	var tdata: Dictionary = GameData.tactical
	map = TacticalMap.generate(pid, int(tdata.get("grid_size", 20)), tdata.get("tiles", {}))
	deployment = TacticalDeployment.new(map)
	deployment.province = pid
	deployment.attacker = attacker
	deployment.defender = defender
	turn = 1
	turn_limit = int(tdata.get("turn_limit", 20))
	phase = "deployment"
	battle = null
	action_mode = "move"
	selected_unit = -1
	player_side = "defender" if GameState.player_nation == defender else "attacker"
	var stats: Dictionary = tdata.get("units", {})
	for d in attacker_divs:
		_add_division("attacker", d, stats)
	for d in defender_divs:
		_add_division("defender", d, stats)
	deployment.auto_deploy("attacker")
	deployment.auto_deploy("defender")
	grid.attacker_color = _nation_color(attacker, Color(0.8, 0.3, 0.3))
	grid.defender_color = _nation_color(defender, Color(0.3, 0.45, 0.85))
	if grid.attacker_color.is_equal_approx(grid.defender_color):
		grid.defender_color = grid.defender_color.inverted()
	grid.setup(map, deployment, _tile_size())
	grid.battle = null
	grid.mode = "move"
	grid.position = _grid_origin()
	grid.selected_unit = -1
	title_label.text = "Battle for %s" % GameData.province_name(pid)
	_rebuild_unit_list()
	_refresh()


func _add_division(side: String, d: DivisionState, stats: Dictionary) -> void:
	var tmpl: Dictionary = GameData.divisions.get(d.template, {})
	var types: Array = tmpl.get("tactical_units", ["infantry", "infantry", "infantry"])
	var n: NationState = GameState.nation(d.owner)
	var max_hp := float(TechEffects.division_stats(d.template, n.researched if n else []).get("hp", 100.0))
	deployment.add_division(side, d.owner, d.id, types, stats, d.hp / maxf(1.0, max_hp))


func _nation_color(nid: String, fallback: Color) -> Color:
	return GameData.nation_color(nid) if nid != "" and GameData.nations.has(nid) else fallback


func _tile_size() -> float:
	var vp := _viewport_size()
	var w := vp.x - LEFT_W - RIGHT_W - PAD * 4
	var h := vp.y - TOP_H - BOTTOM_H - PAD * 2
	var n := float(map.size) if map else 20.0
	return floorf(clampf(minf(w, h) / n, 16.0, 64.0))


func _viewport_size() -> Vector2:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2.ZERO
	return vp if vp.x >= 800 and vp.y >= 600 else Vector2(1920, 1080)


func _grid_origin() -> Vector2:
	var vp := _viewport_size()
	var area_x := LEFT_W + PAD * 2
	var area_w := vp.x - LEFT_W - RIGHT_W - PAD * 4
	var gsize := grid.custom_minimum_size
	return Vector2(area_x + maxf(0.0, (area_w - gsize.x) * 0.5), TOP_H + PAD)


# --- UI construction ---------------------------------------------------------------

func _build_ui() -> void:
	if _built:
		return
	_built = true
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.08, 0.08, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Top bar: title, phase, turn counter (top-right).
	var top := PanelContainer.new()
	top.name = "TopBar"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 24)
	top.add_child(th)
	title_label = UIStyle.label("Battle", 22, UIStyle.ACCENT)
	th.add_child(title_label)
	phase_label = UIStyle.label("", 16, UIStyle.TEXT)
	phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(phase_label)
	turn_label = UIStyle.label("Turn 1 / 20", 20, UIStyle.TEXT)
	turn_label.name = "TurnLabel"
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	th.add_child(turn_label)

	# Left: unit list.
	var left := PanelContainer.new()
	left.name = "UnitPanel"
	left.anchor_bottom = 1.0
	left.offset_left = PAD
	left.offset_right = PAD + LEFT_W
	left.offset_top = TOP_H + PAD
	left.offset_bottom = -(BOTTOM_H + PAD)
	add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIStyle.section_header("Your units"))
	reserve_label = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	lv.add_child(reserve_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	unit_list = VBoxContainer.new()
	unit_list.name = "UnitList"
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_list)

	# Right: tile info + legend.
	var right := PanelContainer.new()
	right.name = "InfoPanel"
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -(RIGHT_W + PAD)
	right.offset_right = -PAD
	right.offset_top = TOP_H + PAD
	right.offset_bottom = -(BOTTOM_H + PAD)
	add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UIStyle.section_header("Tile"))
	tile_info = UIStyle.label("Hover a tile", 14, UIStyle.TEXT)
	tile_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_info.custom_minimum_size = Vector2(RIGHT_W - 30, 110)
	rv.add_child(tile_info)
	rv.add_child(UIStyle.section_header("Legend"))
	var legend := GridContainer.new()
	legend.name = "Legend"
	legend.columns = 2
	rv.add_child(legend)
	var defs: Dictionary = GameData.tactical.get("tiles", TacticalMap.DEFAULT_TILES)
	for tid in TacticalMap.TILE_TYPES:
		var def: Dictionary = defs.get(tid, TacticalMap.DEFAULT_TILES[tid])
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(18, 18)
		sw.color = Color.html(str(def.get("color", "#ff00ff")))
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		legend.add_child(sw)
		legend.add_child(UIStyle.label(_tile_summary(def), 13, UIStyle.TEXT))
	var obj_sw := ColorRect.new()
	obj_sw.custom_minimum_size = Vector2(18, 18)
	obj_sw.color = TacticalGrid.OBJECTIVE
	legend.add_child(obj_sw)
	legend.add_child(UIStyle.label("Objective (attacker must take all 3)", 13, UIStyle.TEXT))
	hint_label = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(RIGHT_W - 30, 0)
	rv.add_child(hint_label)
	rv.add_child(UIStyle.section_header("Battle log"))
	log_label = UIStyle.label("", 12, UIStyle.TEXT_DIM)
	log_label.name = "BattleLog"
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(RIGHT_W - 30, 0)
	rv.add_child(log_label)

	# Bottom: action bar.
	var bottom := PanelContainer.new()
	bottom.name = "ActionBar"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -BOTTOM_H
	add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(bh)
	for a in ACTIONS:
		var b := Button.new()
		b.name = a.replace(" ", "")
		b.text = a
		b.custom_minimum_size = Vector2(108, 44)
		b.disabled = true
		b.tooltip_text = "Available once the battle starts"
		var action := a
		b.pressed.connect(func() -> void: press_action(action))
		bh.add_child(b)
		action_buttons[a] = b
	bh.add_child(VSeparator.new())
	start_button = Button.new()
	start_button.name = "StartBattle"
	start_button.text = "Start battle"
	start_button.tooltip_text = "End deployment and begin turn 1 (attacker moves first)"
	start_button.custom_minimum_size = Vector2(130, 44)
	start_button.pressed.connect(start_battle)
	bh.add_child(start_button)
	auto_deploy_button = Button.new()
	auto_deploy_button.name = "AutoDeploy"
	auto_deploy_button.text = "Auto-deploy"
	auto_deploy_button.custom_minimum_size = Vector2(130, 44)
	auto_deploy_button.pressed.connect(auto_deploy)
	bh.add_child(auto_deploy_button)
	withdraw_button = Button.new()
	withdraw_button.name = "Withdraw"
	withdraw_button.text = "To reserve"
	withdraw_button.custom_minimum_size = Vector2(120, 44)
	withdraw_button.pressed.connect(func() -> void: withdraw_selected())
	bh.add_child(withdraw_button)
	return_button = Button.new()
	return_button.name = "ReturnButton"
	return_button.text = "Return to map"
	return_button.tooltip_text = "Leave the tactical view; the battle is auto-resolved"
	return_button.custom_minimum_size = Vector2(150, 44)
	return_button.pressed.connect(close)
	bh.add_child(return_button)

	grid = TacticalGrid.new()
	grid.name = "Grid"
	add_child(grid)
	grid.tile_clicked.connect(_on_tile_clicked)
	grid.tile_hovered.connect(_on_tile_hovered)


func _tile_summary(def: Dictionary) -> String:
	var parts: PackedStringArray = [str(def.get("name", "?"))]
	if not bool(def.get("passable", true)):
		parts.append("impassable")
	else:
		var db := float(def.get("defense_bonus", 0.0))
		if db > 0.0:
			parts.append("+%d%% def" % int(round(db * 100)))
		if int(def.get("move_cost", 1)) > 1:
			parts.append("move x%d" % int(def.get("move_cost", 1)))
	return ", ".join(parts)


func _rebuild_unit_list() -> void:
	for c in unit_list.get_children():
		unit_list.remove_child(c)
		c.queue_free()
	unit_buttons.clear()
	var last_div := -2
	for u in deployment.units_of(player_side):
		if u.division_id != last_div:
			last_div = u.division_id
			var d: DivisionState = GameState.division(u.division_id)
			var dname := "Division #%d" % u.division_id
			if d:
				dname = "%s #%d" % [str(GameData.divisions.get(d.template, {}).get("name", d.template)), d.id]
			unit_list.add_child(UIStyle.label(dname, 13, UIStyle.ACCENT))
		var b := Button.new()
		b.name = "Unit_%d" % u.id
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(LEFT_W - 40, 30)
		var uid := u.id
		b.pressed.connect(func() -> void: select_unit(uid))
		unit_list.add_child(b)
		unit_buttons[u.id] = b
	var enemy := deployment.units_of("defender" if player_side == "attacker" else "attacker")
	unit_list.add_child(HSeparator.new())
	unit_list.add_child(UIStyle.label("Enemy: %d units" % enemy.size(), 13, UIStyle.TEXT_DIM))


# --- Interaction -------------------------------------------------------------------

func select_unit(uid: int) -> void:
	var u := deployment.unit(uid) if deployment else null
	if u == null or u.side != player_side or (battle != null and not u.is_active()):
		uid = -1
	selected_unit = uid
	grid.selected_unit = uid
	set_action_mode("move")
	unit_selected.emit(uid)
	_refresh()


func _on_tile_clicked(t: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		select_unit(-1)
		return
	click_tile(t)


## Left click on tile [param t]: select an own unit there, or place the selected unit.
func click_tile(t: Vector2i) -> void:
	if phase == "battle":
		_battle_click(t)
		return
	if deployment == null or phase != "deployment":
		return
	var u := deployment.unit_at(t)
	if selected_unit >= 0 and (u == null or u.id != selected_unit):
		var err := deployment.placement_error(selected_unit, t)
		if err == "":
			deployment.place_unit(selected_unit, t)
			hint_label.text = ""
			_refresh()
			return
		if u == null or u.side != player_side:
			hint_label.text = err
			_refresh()
			return
	if u != null and u.side == player_side:
		select_unit(u.id)
	else:
		select_unit(-1)


# --- Battle (step 16) --------------------------------------------------------------

func enemy_side() -> String:
	return TacticalBattle.other_side(player_side)


## True while the player may give orders (battle running, player's phase).
func is_player_phase() -> bool:
	return phase == "battle" and battle != null and battle.active_side == player_side


## End deployment and start turn 1. If the player defends, the AI attacker
## plays its phase first.
func start_battle() -> void:
	if deployment == null or phase != "deployment":
		return
	battle = TacticalBattle.new(deployment, GameData.tactical)
	battle.finished.connect(_on_battle_finished)
	phase = "battle"
	battle.start()
	if phase != "battle":
		return
	grid.battle = battle
	hint_label.text = ""
	if battle.active_side != player_side:
		_run_enemy_phase()
	select_unit(-1)
	_refresh()


func _run_enemy_phase() -> void:
	if battle == null or battle.is_finished:
		return
	TacticalAI.run_phase(battle, battle.active_side)
	if not battle.is_finished:
		battle.end_phase()
	turn = battle.turn


## End the player's phase: the AI plays the other side's phase, then control returns.
func end_player_phase() -> void:
	if not is_player_phase():
		return
	battle.end_phase()
	_run_enemy_phase()
	if phase != "battle":
		return
	turn = battle.turn
	select_unit(-1)
	_refresh()


func set_action_mode(mode: String) -> void:
	action_mode = mode
	if grid:
		grid.mode = mode
		grid.queue_redraw()


## Bottom bar button handler.
func press_action(action: String) -> void:
	if not is_player_phase():
		return
	match action:
		"End phase":
			end_player_phase()
			return
		"Move":
			set_action_mode("move")
		"Attack":
			set_action_mode("attack")
		"Overrun":
			set_action_mode("overrun")
		"Barrage":
			set_action_mode("barrage")
		"Dig in":
			if selected_unit >= 0:
				_report(battle.dig_in(selected_unit), battle.ability_error(selected_unit))
		"Overwatch":
			if selected_unit >= 0:
				_report(battle.set_overwatch(selected_unit), battle.overwatch_error(selected_unit))
	_refresh()


func _report(ok: bool, reason: String) -> void:
	hint_label.text = "" if ok else reason
	if ok:
		set_action_mode("move")


func _battle_click(t: Vector2i) -> void:
	if battle == null or not map.in_bounds(t):
		return
	var u := battle.unit_at(t)
	if not is_player_phase():
		if u != null and u.side == player_side:
			select_unit(u.id)
		return
	if selected_unit < 0 or (u != null and u.side == player_side and u.id != selected_unit and action_mode != "barrage"):
		select_unit(u.id if u != null and u.side == player_side else -1)
		return
	if u != null and u.id == selected_unit:
		set_action_mode("move")
		_refresh()
		return
	match action_mode:
		"attack":
			if u == null or u.side == player_side:
				hint_label.text = "Pick an enemy unit in range"
			else:
				var err := battle.attack_error(selected_unit, u.id)
				_report(battle.attack(selected_unit, u.id) >= 0, err)
		"overrun":
			var err := battle.ability_error(selected_unit, t)
			_report(battle.overrun(selected_unit, u.id) if u != null and err == "" else false, err)
		"barrage":
			var err := battle.ability_error(selected_unit, t)
			_report(battle.barrage(selected_unit, t), err)
		_:
			if u != null and u.side != player_side:
				var err := battle.attack_error(selected_unit, u.id)
				_report(battle.attack(selected_unit, u.id) >= 0, err)
			else:
				var err := battle.move_error(selected_unit, t)
				_report(battle.move_unit(selected_unit, t), err)
	var sel := battle.unit(selected_unit)
	if sel != null and not sel.is_active():
		select_unit(-1)
		return
	_refresh()


## "" if the action button is usable for the selected unit now, else why not.
func action_error(action: String) -> String:
	if phase != "battle" or battle == null:
		return "Start the battle first"
	if battle.active_side != player_side:
		return "Enemy phase"
	if action == "End phase":
		return ""
	var u := battle.unit(selected_unit) if selected_unit >= 0 else null
	if u == null:
		return "Select a unit"
	if not u.is_active():
		return "Unit is not on the battlefield"
	match action:
		"Move":
			return "" if u.moves_left > 0 else "No movement points left"
		"Attack":
			if u.acted:
				return "Already acted this turn"
			return "" if not battle.attack_targets(u.id).is_empty() else "No enemy in range (%d)" % u.attack_range
		"Dig in", "Overrun", "Barrage":
			var needed: String = {"Dig in": "dig_in", "Overrun": "overrun", "Barrage": "barrage"}[action]
			if u.ability != needed:
				return "Only %s can %s" % [{"dig_in": "infantry", "overrun": "armor", "barrage": "artillery"}[needed], action.to_lower()]
			return battle.ability_error(u.id)
		"Overwatch":
			return battle.overwatch_error(u.id)
	return ""


func auto_deploy() -> void:
	if deployment == null or phase != "deployment":
		return
	deployment.auto_deploy(player_side)
	_refresh()


func withdraw_selected() -> void:
	if deployment and selected_unit >= 0 and phase == "deployment":
		deployment.withdraw(selected_unit)
		_refresh()


func _on_tile_hovered(t: Vector2i) -> void:
	tile_info.text = tile_text(t)


## Description of tile [param t] for the info panel.
func tile_text(t: Vector2i) -> String:
	if map == null or not map.in_bounds(t):
		return "Hover a tile"
	var lines: PackedStringArray = ["%s  (%d, %d)" % [map.tile_name(t), t.x, t.y]]
	if not map.is_passable(t):
		lines.append("Impassable")
	else:
		lines.append("Move cost: %d" % map.move_cost(t))
		lines.append("Defense: +%d%%" % int(round(map.defense_bonus(t) * 100)))
	if map.is_objective(t):
		lines.append("Objective %d" % (map.objectives.find(t) + 1))
	var z := map.zone_of(t)
	if z != "":
		lines.append("%s deployment zone" % z.capitalize())
	var u := deployment.unit_at(t) if deployment else null
	if u:
		lines.append("%s (%s) %d/%d HP" % [u.name, GameData.nation_name(u.nation), u.hp, u.max_hp])
		lines.append("Attack %d, defense %d, range %d, move %d" % [u.attack, u.base_defense(), u.attack_range, u.movement])
		if u.dug_in:
			lines.append("Dug in (+%d defense)" % TacticalUnit.DIG_IN_DEFENSE)
		if u.overwatch:
			lines.append("On overwatch")
	return "\n".join(lines)


## Leave the view. Before the battle ended this is an early exit: the losses so
## far are applied (Combat.abandon_tactical) and the strategic battle auto-resolves.
func close() -> void:
	if phase != "finished":
		var combat := get_node_or_null("/root/Combat")
		if combat and province != "":
			combat.abandon_tactical(province, battle.result().casualties if battle else {})
	closed.emit(province)


## Result of the finished battle (step 17), kept for the caller / tests.
var last_result: Dictionary = {}


## The TacticalBattle ended: apply the result to the strategic divisions
## (Combat.apply_tactical_result, casualties keyed by division id), report it and
## return to the map.
func _on_battle_finished(winner: String, _reason: String) -> void:
	phase = "finished"
	last_result = battle.result()
	var combat := get_node_or_null("/root/Combat")
	if combat and province != "":
		combat.apply_tactical_result(province, winner == "attacker", last_result.casualties)
	var won := winner == player_side
	EventBus.notify.emit("Battle for %s: %s (%s)" % [GameData.province_name(province),
		"victory" if won else "defeat", str(last_result.reason).replace("_", " ")])
	close.call_deferred()


func _refresh() -> void:
	if deployment == null:
		return
	if battle:
		turn = battle.turn
	turn_label.text = "Turn %d / %d" % [turn, turn_limit]
	var side_name := GameData.nation_name(deployment.attacker if player_side == "attacker" else deployment.defender)
	var vs := "%s vs %s" % [GameData.nation_name(deployment.attacker) if deployment.attacker != "" else "-",
		GameData.nation_name(deployment.defender)]
	if phase == "battle":
		var whose := "Your phase" if is_player_phase() else "Enemy phase"
		var mode_txt := "" if selected_unit < 0 else "  |  Mode: %s" % action_mode.capitalize()
		phase_label.text = "%s - %s (%s)%s  |  %s" % [whose, side_name, player_side, mode_txt, vs]
	else:
		phase_label.text = "Deployment - %s (%s)  |  %s" % [side_name, player_side, vs]
	for uid in unit_buttons:
		var u := deployment.unit(uid)
		var b: Button = unit_buttons[uid]
		b.text = unit_text(u)
		b.disabled = u.destroyed
		b.set_pressed_no_signal(uid == selected_unit)
	if phase == "battle":
		reserve_label.text = "%d active, %d destroyed. Select a unit: green = move, red = targets." % [
			battle.active_units(player_side).size(),
			deployment.units_of(player_side).filter(func(x: TacticalUnit) -> bool: return x.destroyed).size()]
	else:
		reserve_label.text = "%d deployed, %d in reserve. Select a unit, then click a highlighted tile." % [
			deployment.units_of(player_side).size() - deployment.reserve(player_side).size(),
			deployment.reserve(player_side).size()]
	var deploying := phase == "deployment"
	withdraw_button.visible = deploying
	auto_deploy_button.visible = deploying
	start_button.visible = deploying
	withdraw_button.disabled = selected_unit < 0
	for a in action_buttons:
		var btn: Button = action_buttons[a]
		var err := action_error(a)
		btn.disabled = err != ""
		btn.tooltip_text = err if err != "" else _action_tooltip(a)
		btn.toggle_mode = a in ["Move", "Attack", "Overrun", "Barrage"]
		btn.set_pressed_no_signal(btn.toggle_mode and selected_unit >= 0 and a.to_lower() == action_mode)
	if battle:
		var n := battle.log_lines.size()
		log_label.text = "\n".join(battle.log_lines.slice(maxi(0, n - LOG_LINES), n))
	else:
		log_label.text = ""
	grid.queue_redraw()


func _action_tooltip(action: String) -> String:
	match action:
		"Move":
			return "Click a green tile to move (costs movement points)"
		"Attack":
			return "Click a red enemy in range (uses the action, ends movement)"
		"Dig in":
			return "+%d defense until the unit moves (uses the action)" % TacticalUnit.DIG_IN_DEFENSE
		"Overrun":
			return "Click an enemy within reach: move and attack in one action"
		"Barrage":
			return "Click a tile in range: full damage there, half on adjacent tiles"
		"Overwatch":
			return "Skip the action; fire at the first enemy that moves within range"
		"End phase":
			return "End your phase; the enemy moves"
	return ""


## Unit list line: letter, name, HP, position/status, MP and flags.
func unit_text(u: TacticalUnit) -> String:
	if u.destroyed:
		return "%s %s  destroyed" % [u.letter(), u.name]
	var where := "(%d,%d)" % [u.pos.x, u.pos.y] if u.is_deployed() else "reserve"
	var s := "%s %s  %d/%d HP  %s" % [u.letter(), u.name, u.hp, u.max_hp, where]
	if phase == "battle" and u.is_deployed():
		s += "  MP %d" % u.moves_left
		if u.acted:
			s += "  acted"
		if u.dug_in:
			s += "  dug in"
		if u.overwatch:
			s += "  overwatch"
	return s
