class_name ProductionPanel
extends VBoxContainer
## Contents of the side panel's "Production" tab (step 6).
## Factory assignment per equipment type (-/+ buttons), output per day,
## stockpiles, steel/oil balance, "Build factory" per owned province and the
## construction queue. Talks to the Production autoload for the player nation.
##
## Rows are built once and updated in place (refresh, at most once per frame)
## so button presses are not lost when days pass quickly.
## Node names for tests: Equip_<eq> (children Minus, Plus, Assigned, Output, Stock,
## Shortage), FactorySummary, Resource_<steel|oil>, Build_<pid>, Construction.

var summary_label: Label
## eq -> {"row", "minus", "plus", "assigned", "output", "stock", "shortage"}
var equip_rows: Dictionary = {}
## "steel"/"oil" -> Label
var resource_labels: Dictionary = {}
var build_box: VBoxContainer
## pid -> Button
var build_buttons: Dictionary = {}
var construction_box: VBoxContainer
var _built_for: PackedStringArray = []
var _dirty := true


func _ready() -> void:
	name = "ProductionPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build()
	EventBus.game_state_ready.connect(mark_dirty)
	EventBus.day_passed.connect(func(_d: int) -> void: mark_dirty())
	EventBus.nation_changed.connect(func(_n: String) -> void: mark_dirty())
	EventBus.province_changed.connect(func(_p: String) -> void: mark_dirty())
	EventBus.factory_completed.connect(func(_p: String) -> void: mark_dirty())
	refresh()


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func _production() -> Node:
	return get_node_or_null("/root/Production")


func _build() -> void:
	add_child(UIStyle.section_header("Factories"))
	summary_label = UIStyle.label("", 15)
	summary_label.name = "FactorySummary"
	add_child(summary_label)

	add_child(UIStyle.section_header("Equipment"))
	for eq in GameData.equipment_ids:
		var def: Dictionary = GameData.equipment[eq]
		var box := VBoxContainer.new()
		box.name = "Equip_" + eq
		box.add_theme_constant_override("separation", 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var title := UIStyle.label(String(def.get("name", eq)), 16)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var minus := _small_button("Minus", "-")
		minus.tooltip_text = "Remove a factory (Shift: 5)"
		minus.pressed.connect(func() -> void: _change(eq, -_step()))
		row.add_child(minus)
		var assigned := UIStyle.label("0", 16, UIStyle.ACCENT)
		assigned.name = "Assigned"
		assigned.custom_minimum_size.x = 34
		assigned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(assigned)
		var plus := _small_button("Plus", "+")
		plus.tooltip_text = "Assign a free factory (Shift: 5)"
		plus.pressed.connect(func() -> void: _change(eq, _step()))
		row.add_child(plus)
		box.add_child(row)
		var info := HBoxContainer.new()
		var output := UIStyle.label("", 13, UIStyle.TEXT_DIM)
		output.name = "Output"
		output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(output)
		var stock := UIStyle.label("", 13, UIStyle.TEXT)
		stock.name = "Stock"
		info.add_child(stock)
		box.add_child(info)
		var res: Dictionary = def.get("resources", {})
		var cost_parts: PackedStringArray = ["%.1f pts" % float(def.get("cost", 0.0))]
		for k in ["steel", "oil"]:
			if float(res.get(k, 0.0)) > 0.0:
				cost_parts.append("%s %s" % [str(float(res[k])), k])
		var cost := UIStyle.label("Per unit: " + ", ".join(cost_parts), 12, UIStyle.TEXT_DIM)
		box.add_child(cost)
		var shortage := UIStyle.label("Stalled: not enough steel/oil", 12, UIStyle.BAD)
		shortage.name = "Shortage"
		shortage.visible = false
		box.add_child(shortage)
		add_child(box)
		# find_child needs owned nodes; keep direct references instead.
		minus.name = "Minus"
		equip_rows[eq] = {"row": box, "minus": minus, "plus": plus, "assigned": assigned,
			"output": output, "stock": stock, "shortage": shortage}

	add_child(UIStyle.section_header("Resources per day"))
	for k in ["steel", "oil"]:
		var l := UIStyle.label("", 14)
		l.name = "Resource_" + k
		add_child(l)
		resource_labels[k] = l

	add_child(UIStyle.section_header("Build factories"))
	var cost_note := UIStyle.label("", 12, UIStyle.TEXT_DIM)
	cost_note.name = "BuildNote"
	cost_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_note.custom_minimum_size.x = UIStyle.RIGHT_PANEL_WIDTH - 60
	add_child(cost_note)
	build_box = VBoxContainer.new()
	build_box.name = "BuildList"
	build_box.add_theme_constant_override("separation", 3)
	add_child(build_box)

	add_child(UIStyle.section_header("Under construction"))
	construction_box = VBoxContainer.new()
	construction_box.name = "Construction"
	construction_box.add_theme_constant_override("separation", 3)
	add_child(construction_box)


func _small_button(node_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 28)
	return b


func _step() -> int:
	return 5 if Input.is_key_pressed(KEY_SHIFT) else 1


func _change(eq: String, delta: int) -> void:
	var prod := _production()
	if prod and GameState.active:
		prod.change_allocation(GameState.player_nation, eq, delta)
	refresh()


func _build_pressed(pid: String) -> void:
	var prod := _production()
	if prod and GameState.active:
		prod.build_factory(GameState.player_nation, pid)
	refresh()


func refresh() -> void:
	_dirty = false
	var prod := _production()
	var active: bool = GameState.active and prod != null and GameState.player() != null
	var nid: String = GameState.player_nation if active else ""
	var n: NationState = GameState.player() if active else null
	if not active:
		summary_label.text = "No game running"
	else:
		summary_label.text = "%d factories: %d assigned, %d free   (x%.2f output)" % [
			prod.available_factories(nid), prod.allocated_total(nid), prod.free_factories(nid),
			float(prod.points_per_factory(nid))]
	for eq in equip_rows:
		var r: Dictionary = equip_rows[eq]
		if not active:
			r.assigned.text = "-"
			r.output.text = ""
			r.stock.text = ""
			r.minus.disabled = true
			r.plus.disabled = true
			r.shortage.visible = false
			continue
		var a: int = prod.allocation(nid, eq)
		r.assigned.text = str(a)
		r.output.text = "%.2f / day" % float(prod.daily_output(nid, eq))
		r.stock.text = "Stockpile %s" % UIStyle.fmt_int(float(n.stockpile.get(eq, 0.0)))
		r.minus.disabled = a <= 0
		r.plus.disabled = prod.free_factories(nid) <= 0
		r.shortage.visible = prod.is_short(nid, eq)
	for k in resource_labels:
		if not active:
			resource_labels[k].text = ""
			continue
		var inc: Dictionary = prod.resource_income(nid)
		var use: Dictionary = prod.daily_resource_use(nid)
		var net := float(inc[k]) - float(use[k])
		resource_labels[k].text = "%s: +%.1f income, -%.1f production = %s%.1f   (stock %s)" % [
			String(k).capitalize(), float(inc[k]), float(use[k]), "+" if net >= 0.0 else "", net,
			UIStyle.fmt_int(float(n.stockpile.get(k, 0.0)))]
		resource_labels[k].add_theme_color_override("font_color", UIStyle.TEXT if net >= 0.0 else UIStyle.BAD)
	var note: Label = get_node("BuildNote")
	note.text = ("A factory costs %d steel and takes %d days." % [int(prod.factory_build_cost()), prod.factory_build_days()]) if prod else ""
	_refresh_build_list(prod, nid, active)
	_refresh_construction(prod, nid, active)


func _refresh_build_list(prod: Node, nid: String, active: bool) -> void:
	var pids: PackedStringArray = prod.buildable_provinces(nid) if active else PackedStringArray()
	if pids != _built_for:
		_built_for = pids
		build_buttons.clear()
		for c in build_box.get_children():
			build_box.remove_child(c)
			c.queue_free()
		for pid in pids:
			var row := HBoxContainer.new()
			var l := UIStyle.label(GameData.province_name(pid), 14)
			l.name = "Name"
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var b := Button.new()
			b.name = "Build_" + pid
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(130, 26)
			b.pressed.connect(_build_pressed.bind(pid))
			row.add_child(b)
			build_box.add_child(row)
			build_buttons[pid] = b
	if pids.is_empty() and build_box.get_child_count() == 0:
		build_box.add_child(UIStyle.label("No provinces to build in", 13, UIStyle.TEXT_DIM))
	for pid in build_buttons:
		var b: Button = build_buttons[pid]
		var ps: ProvinceState = GameState.province(pid)
		var row: HBoxContainer = b.get_parent()
		var queued := ps.factory_queue.size()
		row.get_node("Name").text = "%s  (%d%s)" % [GameData.province_name(pid), ps.factories,
			(" +%d" % queued) if queued > 0 else ""]
		var err: String = prod.build_factory_error(nid, pid)
		b.text = "Build factory"
		b.disabled = err != ""
		b.tooltip_text = err if err != "" else "Spend %d steel to start a factory here." % int(prod.factory_build_cost())


func _refresh_construction(prod: Node, nid: String, active: bool) -> void:
	for c in construction_box.get_children():
		construction_box.remove_child(c)
		c.queue_free()
	var items: Array = prod.construction_list(nid) if active else []
	if items.is_empty():
		construction_box.add_child(UIStyle.label("Nothing under construction", 13, UIStyle.TEXT_DIM))
		return
	var total := float(prod.factory_build_days())
	for it: Dictionary in items:
		var row := HBoxContainer.new()
		row.name = "Item"
		var l := UIStyle.label("%s: %d days%s" % [GameData.province_name(it.province), int(it.days_left),
			" (paused, occupied)" if it.paused else ""], 13)
		l.custom_minimum_size.x = 210
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = clampf(1.0 - float(it.days_left) / maxf(1.0, total), 0.0, 1.0)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		construction_box.add_child(row)
