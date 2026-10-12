class_name RecruitPanel
extends VBoxContainer
## Recruitment section of the "Production" tab (step 8), below ProductionPanel.
## Deployment province picker (owned + controlled land provinces; default the
## capital, follows the map selection when the player owns the selected
## province), one Recruit button per division type with its cost, and the
## training queue with Cancel buttons (full refund).
## Node names for tests: Manpower, Deploy (OptionButton), Recruit_<template>, Queue.

var manpower_label: Label
var deploy_option: OptionButton
## template -> Button
var recruit_buttons: Dictionary = {}
var queue_box: VBoxContainer
## Currently chosen deployment province.
var deploy_province: String = ""
var _deploy_list: PackedStringArray = []
var _dirty := true


func _ready() -> void:
	name = "RecruitPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build()
	EventBus.game_state_ready.connect(func() -> void:
		deploy_province = ""
		mark_dirty())
	EventBus.day_passed.connect(func(_d: int) -> void: mark_dirty())
	EventBus.nation_changed.connect(func(_n: String) -> void: mark_dirty())
	EventBus.province_changed.connect(func(_p: String) -> void: mark_dirty())
	EventBus.division_created.connect(func(_d: int) -> void: mark_dirty())
	EventBus.province_selected.connect(_on_province_selected)
	refresh()


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func _rec() -> Node:
	return get_node_or_null("/root/Recruitment")


func _build() -> void:
	add_child(UIStyle.section_header("Recruitment"))
	manpower_label = UIStyle.label("", 14)
	manpower_label.name = "Manpower"
	add_child(manpower_label)
	var row := HBoxContainer.new()
	row.add_child(UIStyle.label("Deploy to:", 14))
	deploy_option = OptionButton.new()
	deploy_option.name = "Deploy"
	deploy_option.focus_mode = Control.FOCUS_NONE
	deploy_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_option.item_selected.connect(_on_deploy_selected)
	row.add_child(deploy_option)
	add_child(row)
	for tid in GameData.division_ids:
		var b := Button.new()
		b.name = "Recruit_" + tid
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(_recruit_pressed.bind(tid))
		add_child(b)
		recruit_buttons[tid] = b
	add_child(UIStyle.section_header("In training"))
	queue_box = VBoxContainer.new()
	queue_box.name = "Queue"
	add_child(queue_box)


func set_deploy_province(pid: String) -> void:
	var rec := _rec()
	if rec and GameState.active and rec.is_valid_deploy(GameState.player_nation, pid):
		deploy_province = pid
	mark_dirty()


func _on_province_selected(pid: String) -> void:
	set_deploy_province(pid)


func _on_deploy_selected(index: int) -> void:
	if index >= 0 and index < _deploy_list.size():
		deploy_province = _deploy_list[index]
	mark_dirty()


func _recruit_pressed(tid: String) -> void:
	var rec := _rec()
	if rec and GameState.active:
		rec.recruit(GameState.player_nation, tid, deploy_province)
	refresh()


func _cancel_pressed(index: int) -> void:
	var rec := _rec()
	if rec and GameState.active:
		rec.cancel_recruit(GameState.player_nation, index)
	refresh()


func refresh() -> void:
	_dirty = false
	var rec := _rec()
	var active: bool = rec != null and GameState.active and GameState.player() != null
	var nid: String = GameState.player_nation if active else ""
	# Deployment list
	var pids: PackedStringArray = rec.deploy_provinces(nid) if active else PackedStringArray()
	if active and not pids.has(deploy_province):
		deploy_province = rec.default_deploy_province(nid)
	if pids != _deploy_list:
		_deploy_list = pids
		deploy_option.clear()
		for pid in pids:
			deploy_option.add_item(GameData.province_name(pid))
	deploy_option.disabled = pids.is_empty()
	var idx := _deploy_list.find(deploy_province)
	if idx >= 0 and deploy_option.selected != idx:
		deploy_option.select(idx)
	manpower_label.text = ("Manpower: %s" % UIStyle.fmt_int(GameState.player().manpower)) if active else "No game running"
	for tid in recruit_buttons:
		var b: Button = recruit_buttons[tid]
		var tname := String(GameData.divisions[tid].get("name", tid))
		if not active:
			b.text = tname
			b.disabled = true
			continue
		b.text = "Recruit %s  (%s)" % [tname, rec.cost_text(tid)]
		var err: String = rec.recruit_error(nid, tid, deploy_province)
		b.disabled = err != ""
		b.tooltip_text = err if err != "" else "Recruit in %s" % GameData.province_name(deploy_province)
	_refresh_queue(rec, nid, active)


func _refresh_queue(rec: Node, nid: String, active: bool) -> void:
	for c in queue_box.get_children():
		queue_box.remove_child(c)
		c.queue_free()
	var items: Array = rec.queue(nid) if active else []
	if items.is_empty():
		queue_box.add_child(UIStyle.label("No divisions in training", 13, UIStyle.TEXT_DIM))
		return
	for i in items.size():
		var it: Dictionary = items[i]
		var row := HBoxContainer.new()
		row.name = "Item%d" % i
		var l := UIStyle.label("%s - %s: %d days" % [String(GameData.divisions[it.template].get("short", it.template)),
			GameData.province_name(it.province), int(it.days_left)], 13)
		l.custom_minimum_size.x = 210
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = float(it.progress)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(100, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var x := Button.new()
		x.name = "Cancel"
		x.text = "X"
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = "Cancel (full refund)"
		x.pressed.connect(_cancel_pressed.bind(i))
		row.add_child(x)
		queue_box.add_child(row)
