class_name InfoPanel
extends PanelContainer
## Left panel, shown on click: province info (name, terrain, owner,
## garrison, resources, buildings) or division info (type, stats, orders).
##
## Listens to EventBus.province_selected / selection_cleared / division_selected.
## Content is rebuilt (at most once per frame) whenever relevant state changes.
## API: show_province(pid), show_division(did), close(), mode ("", "province",
## "division"), current_province, current_division, content (VBoxContainer).
## Later steps can add sections by connecting to `content_built(mode)` and
## appending children to `content`.

signal content_built(mode: String)

const MAX_GARRISON_ROWS := 7

var mode: String = ""
var current_province: String = ""
var current_division: int = -1
var content: VBoxContainer
var _dirty := false


func _ready() -> void:
	name = "InfoPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(UIStyle.MARGIN, UIStyle.TOP_BAR_HEIGHT + UIStyle.MARGIN)
	custom_minimum_size = Vector2(UIStyle.LEFT_PANEL_WIDTH, 0)
	content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	visible = false
	EventBus.province_selected.connect(show_province)
	EventBus.selection_cleared.connect(close)
	EventBus.division_selected.connect(show_division)
	EventBus.game_state_ready.connect(_on_game_state_ready)
	for sig in ["province_changed", "nation_changed", "day_passed", "division_created", "division_destroyed",
			"battle_started", "battle_ended", "province_captured"]:
		EventBus.connect(sig, _mark_dirty_any)
	EventBus.division_moved.connect(func(_d: int, _a: String, _b: String) -> void: mark_dirty())
	EventBus.division_order_changed.connect(func(_d: int) -> void: mark_dirty())
	EventBus.divisions_selected.connect(_on_divisions_selected)


func show_province(pid: String) -> void:
	if pid == "" or GameData.province(pid).is_empty():
		close()
		return
	mode = "province"
	current_province = pid
	current_division = -1
	visible = true
	rebuild()


func show_division(did: int) -> void:
	var d: DivisionState = GameState.division(did)
	if d == null:
		return
	mode = "division"
	group_size = 1
	current_division = did
	current_province = d.province
	visible = true
	rebuild()


## Step 9: number of divisions selected together on the map (group move).
var group_size: int = 1


func _on_divisions_selected(ids: Array) -> void:
	if ids.is_empty():
		group_size = 1
		if mode == "division":
			mark_dirty()
		return
	show_division(int(ids[0]))
	group_size = ids.size()
	rebuild()


func close() -> void:
	mode = ""
	current_province = ""
	current_division = -1
	visible = false
	_clear()


func mark_dirty() -> void:
	_dirty = true


func _mark_dirty_any(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_dirty = true


func _on_game_state_ready() -> void:
	close()


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		if visible:
			rebuild()


func rebuild() -> void:
	_clear()
	match mode:
		"province":
			_build_province(current_province)
		"division":
			if GameState.division(current_division) == null:
				# Division gone (destroyed): fall back to its last province.
				mode = "province"
				current_division = -1
				_build_province(current_province)
			else:
				_build_division(GameState.division(current_division))
	content_built.emit(mode)
	reset_size.call_deferred()


func _clear() -> void:
	if content == null:
		return
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()


# --- Province view -----------------------------------------------------------

func _build_province(pid: String) -> void:
	var def: Dictionary = GameData.province(pid)
	var ps: ProvinceState = GameState.province(pid) if GameState.active else null
	var owner_id: String = ps.owner if ps else String(def.get("owner", ""))
	var controller_id: String = ps.controller if ps else owner_id

	content.add_child(_header(GameData.province_name(pid), _province_subtitle(pid, owner_id)))

	# Owner / controller
	var owner_row := HBoxContainer.new()
	owner_row.name = "OwnerRow"
	owner_row.add_theme_constant_override("separation", 8)
	var flag := FlagView.new()
	flag.custom_minimum_size = Vector2(36, 24)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.set_flag(GameData.nation(controller_id).get("flag", {}))
	owner_row.add_child(flag)
	var owner_text := GameData.nation_name(owner_id)
	var owner_label := UIStyle.label(owner_text, 17)
	owner_label.name = "Owner"
	owner_row.add_child(owner_label)
	content.add_child(owner_row)
	if controller_id != owner_id:
		var occ := UIStyle.label("Occupied by " + GameData.nation_name(controller_id), 14, UIStyle.BAD)
		occ.name = "Occupied"
		content.add_child(occ)

	_build_battle(pid)

	# Terrain
	var terrain: Dictionary = GameData.terrain_of(pid)
	content.add_child(UIStyle.section_header("Terrain"))
	var tgrid := _grid("TerrainGrid")
	_row(tgrid, "Type", String(terrain.get("name", "?")))
	_row(tgrid, "Movement cost", "x%.2f" % float(terrain.get("move_cost", 1.0)))
	_row(tgrid, "Defense bonus", "+%d%%" % roundi(float(terrain.get("defense_bonus", 0.0)) * 100.0))
	content.add_child(tgrid)

	# Resources
	var res: Dictionary = def.get("resources", {})
	content.add_child(UIStyle.section_header("Resources per day"))
	var rgrid := _grid("ResourceGrid")
	for k in ["steel", "oil", "food"]:
		_row(rgrid, String(k).capitalize(), str(int(res.get(k, 0))))
	content.add_child(rgrid)

	# Buildings
	if not GameData.is_naval(pid):
		content.add_child(UIStyle.section_header("Buildings"))
		var bgrid := _grid("BuildingGrid")
		var factories: int = ps.factories if ps else int(def.get("factories", 0))
		var fac_text := str(factories)
		if ps and not ps.factory_queue.is_empty():
			fac_text += "  (+%d building)" % ps.factory_queue.size()
		_row(bgrid, "Factories", fac_text)
		var infra: int = ps.infrastructure if ps else int(def.get("infrastructure", 1))
		_row(bgrid, "Infrastructure", "%d / 5" % infra)
		content.add_child(bgrid)

	# Garrison
	content.add_child(UIStyle.section_header("Garrison"))
	var garrison := VBoxContainer.new()
	garrison.name = "Garrison"
	garrison.add_theme_constant_override("separation", 3)
	var divs: Array = GameState.divisions_in(pid) if GameState.active else []
	divs.sort_custom(func(a: DivisionState, b: DivisionState) -> bool: return a.id < b.id)
	if divs.is_empty():
		garrison.add_child(UIStyle.label("No divisions", 14, UIStyle.TEXT_DIM))
	for d: DivisionState in divs:
		garrison.add_child(_division_button(d))
	if divs.size() > MAX_GARRISON_ROWS:
		var scroll := ScrollContainer.new()
		scroll.name = "GarrisonScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, MAX_GARRISON_ROWS * 34)
		garrison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(garrison)
		content.add_child(scroll)
	else:
		content.add_child(garrison)


## Step 10: battle progress for a province under attack.
func _build_battle(pid: String) -> void:
	var combat := get_node_or_null("/root/Combat")
	if combat == null or not GameState.active or not combat.has_battle(pid):
		return
	var b: Dictionary = combat.battle_at(pid)
	content.add_child(UIStyle.section_header("Battle"))
	var bal: float = combat.balance(pid)
	var txt := "%s attacks %s - day %d\nAttackers: %d divisions   Defenders: %d divisions\nAttacker advantage: %d%%" % [
		GameData.nation_name(b.attacker), GameData.nation_name(b.defender), int(b.days),
		combat.attackers(pid).size(), combat.defenders(pid, b.attacker).size(), roundi(bal * 100.0)]
	var lbl := UIStyle.label(txt, 14, UIStyle.BAD)
	lbl.name = "BattleInfo"
	content.add_child(lbl)
	content.add_child(_bar("Battle", bal, UIStyle.BAD))


func _province_subtitle(pid: String, owner_id: String) -> String:
	if GameData.is_naval(pid):
		return "Naval zone"
	var parts: PackedStringArray = []
	if GameData.is_capital(pid):
		parts.append("Capital of " + GameData.nation_name(owner_id))
	if GameData.is_major_city(pid):
		parts.append("Major city")
	if parts.is_empty():
		parts.append("Province")
	return " - ".join(parts)


func _division_button(d: DivisionState) -> Button:
	var tpl: Dictionary = GameData.divisions.get(d.template, {})
	var b := Button.new()
	b.name = "Division_%d" % d.id
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	var max_hp := _max_stats(d).hp as float
	var hp_pct := 100.0 * d.hp / maxf(1.0, max_hp)
	var txt := "%s  %s  #%d   HP %d%%" % [String(tpl.get("short", "?")), GameData.nation(d.owner).get("adjective", ""), d.id, roundi(hp_pct)]
	if d.is_moving():
		txt += "  -> " + GameData.province_name(d.path[-1])
	b.text = txt
	b.add_theme_color_override("font_color", GameData.nation_color(d.owner).lightened(0.45))
	b.pressed.connect(func() -> void: EventBus.division_selected.emit(d.id))
	return b


# --- Division view -----------------------------------------------------------

func _build_division(d: DivisionState) -> void:
	var tpl: Dictionary = GameData.divisions.get(d.template, {})
	content.add_child(_header("%s #%d" % [String(tpl.get("name", d.template)), d.id],
		"%s - in %s" % [GameData.nation_name(d.owner), GameData.province_name(d.province)]))
	var desc := UIStyle.label(String(tpl.get("description", "")), 13, UIStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = UIStyle.LEFT_PANEL_WIDTH - 30
	content.add_child(desc)

	var stats := _max_stats(d)
	content.add_child(UIStyle.section_header("Stats"))
	var sgrid := _grid("StatsGrid")
	_row(sgrid, "Attack", "%.1f" % float(stats.attack))
	_row(sgrid, "Defense", "%.1f" % float(stats.defense))
	_row(sgrid, "Speed", "%.1f" % float(stats.speed))
	_row(sgrid, "Organization", "%d / %d" % [roundi(d.organization), roundi(float(stats.organization))])
	_row(sgrid, "HP", "%d / %d" % [roundi(d.hp), roundi(float(stats.hp))])
	if float(stats.get("support_attack_bonus", 0.0)) > 0.0:
		_row(sgrid, "Support bonus", "+%d%% attack" % roundi(float(stats.support_attack_bonus) * 100.0))
	if d.entrenchment > 0.0:
		_row(sgrid, "Entrenchment", "%d%%" % roundi(d.entrenchment * 100.0))
	content.add_child(sgrid)
	content.add_child(_bar("HP", d.hp / maxf(1.0, float(stats.hp)), UIStyle.GOOD))
	content.add_child(_bar("Organization", d.organization / maxf(1.0, float(stats.organization)), UIStyle.ACCENT))

	content.add_child(UIStyle.section_header("Orders"))
	var orders := "Holding position"
	if d.is_moving():
		var names: PackedStringArray = []
		for p in d.path:
			names.append(GameData.province_name(p))
		orders = "Moving to %s (%d%% to %s)\nRoute: %s" % [GameData.province_name(d.path[-1]),
			roundi(d.move_progress * 100.0), GameData.province_name(d.path[0]), " > ".join(names)]
	var orders_label := UIStyle.label(orders, 14)
	orders_label.name = "Orders"
	orders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orders_label.custom_minimum_size.x = UIStyle.LEFT_PANEL_WIDTH - 30
	content.add_child(orders_label)
	var mv := get_node_or_null("/root/Movement")
	if d.is_moving() and mv:
		var eta := ceili(float(mv.eta_days(d)) - 0.0001)
		var eta_label := UIStyle.label("Arrives in %d day%s" % [eta, "" if eta == 1 else "s"], 14, UIStyle.TEXT_DIM)
		eta_label.name = "Eta"
		content.add_child(eta_label)
		content.add_child(_bar("Move", d.move_progress, UIStyle.ACCENT))
	if d.owner == GameState.player_nation:
		var hint_text := "Click or right-click a province on the map to move."
		if group_size > 1:
			hint_text = "%d divisions selected. " % group_size + hint_text
		var hint := UIStyle.label(hint_text, 13, UIStyle.ACCENT)
		hint.name = "MoveHint"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = UIStyle.LEFT_PANEL_WIDTH - 30
		content.add_child(hint)
		if d.is_moving() and mv:
			var stop_btn := Button.new()
			stop_btn.name = "StopButton"
			stop_btn.text = "Stop (hold in %s)" % GameData.province_name(d.province)
			stop_btn.focus_mode = Control.FOCUS_NONE
			var did := d.id
			stop_btn.pressed.connect(func() -> void: mv.stop(did))
			content.add_child(stop_btn)

	var back := Button.new()
	back.name = "BackToProvince"
	back.text = "< " + GameData.province_name(d.province)
	back.focus_mode = Control.FOCUS_NONE
	var pid := d.province
	back.pressed.connect(func() -> void:
		EventBus.divisions_selected.emit([])
		show_province(pid))
	content.add_child(back)


func _max_stats(d: DivisionState) -> Dictionary:
	var n: NationState = GameState.nation(d.owner)
	return TechEffects.division_stats(d.template, n.researched if n else [])


# --- Widgets -----------------------------------------------------------------

func _header(title: String, subtitle: String) -> Control:
	var box := HBoxContainer.new()
	box.name = "Header"
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", -2)
	var t := UIStyle.label(title, 24, UIStyle.TEXT)
	t.name = "Title"
	texts.add_child(t)
	var s := UIStyle.label(subtitle, 13, UIStyle.TEXT_DIM)
	s.name = "Subtitle"
	texts.add_child(s)
	box.add_child(texts)
	var close_btn := Button.new()
	close_btn.name = "Close"
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.tooltip_text = "Close"
	close_btn.pressed.connect(_on_close_pressed)
	box.add_child(close_btn)
	return box


func _on_close_pressed() -> void:
	close()
	# MapView listens and drops its selection highlight.
	EventBus.selection_cleared.emit()


func _grid(node_name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = node_name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 2)
	return g


func _row(grid: GridContainer, key: String, value: String) -> void:
	var k := UIStyle.label(key, 14, UIStyle.TEXT_DIM)
	k.custom_minimum_size.x = 140
	grid.add_child(k)
	var v := UIStyle.label(value, 14, UIStyle.TEXT)
	v.name = "Value_" + key.replace(" ", "_")
	grid.add_child(v)


func _bar(title: String, ratio: float, col: Color) -> Control:
	var bar := ProgressBar.new()
	bar.name = "Bar_" + title
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("background", UIStyle.flat_box(Color(0.2, 0.2, 0.22), 3, 0))
	bar.add_theme_stylebox_override("fill", UIStyle.flat_box(col, 3, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.tooltip_text = title
	return bar


## Text of a value row ("Factories", "Type", ...) in the current content, or "".
func value_text(key: String) -> String:
	var n := content.find_child("Value_" + key.replace(" ", "_"), true, false)
	return (n as Label).text if n is Label else ""
