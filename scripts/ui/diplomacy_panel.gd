class_name DiplomacyPanel
extends VBoxContainer
## Contents of the side panel's "Diplomacy" tab (step 13).
## Summary line (wars of the player) and one row per other nation: flag, name,
## relation status (Diplomacy.status_text) and four buttons: Justify (Cancel
## while a war goal exists), Declare war, Offer pact (Break pact when signed),
## Request access. Disabled buttons carry the refusal reason as tooltip.
## Talks to the Diplomacy autoload for the player nation.
##
## Built once per game (rows for every nation except the player), refreshed in
## place at most once per frame. rows[nid] = {"row", "flag", "name", "status",
## "justify", "declare", "pact", "access"}. Node names: Summary, Nations/Row_<nid>.

var summary: Label
var list: VBoxContainer
var rows: Dictionary = {}
var _built_for := "-"
var _dirty := true


func _ready() -> void:
	name = "DiplomacyPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	add_child(UIStyle.section_header("Relations"))
	summary = UIStyle.label("", 14, UIStyle.TEXT)
	summary.name = "Summary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.x = UIStyle.RIGHT_PANEL_WIDTH - 60
	add_child(summary)
	var hint := UIStyle.label("Justify a war goal (%d days) before declaring war. A pact blocks war; access lets your divisions pass." % _goal_days(), 12, UIStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = UIStyle.RIGHT_PANEL_WIDTH - 60
	add_child(hint)
	add_child(UIStyle.section_header("Nations"))
	list = VBoxContainer.new()
	list.name = "Nations"
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	EventBus.game_state_ready.connect(mark_dirty)
	EventBus.day_passed.connect(func(_d: int) -> void: mark_dirty())
	EventBus.nation_changed.connect(func(_n: String) -> void: mark_dirty())
	EventBus.war_declared.connect(func(_a: String, _b: String) -> void: mark_dirty())
	EventBus.pact_signed.connect(func(_a: String, _b: String) -> void: mark_dirty())
	EventBus.military_access_granted.connect(func(_h: String, _g: String) -> void: mark_dirty())
	EventBus.nation_capitulated.connect(func(_n: String, _c: String) -> void: mark_dirty())
	refresh()


func _goal_days() -> int:
	return int(GameData.rule("war_goal_days", 30))


func _dip() -> Node:
	return get_node_or_null("/root/Diplomacy")


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func _player() -> String:
	return GameState.player_nation if GameState.active else ""


func _rebuild_rows(pid: String) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	_built_for = pid
	if pid == "":
		return
	for nid in GameData.nation_ids:
		if nid == pid:
			continue
		var box := PanelContainer.new()
		box.name = "Row_" + nid
		box.add_theme_stylebox_override("panel", UIStyle.flat_box(UIStyle.HEADER_BG, 4, 6))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		box.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		var flag := FlagView.new()
		flag.custom_minimum_size = Vector2(30, 20)
		flag.set_flag(GameData.nation(nid).get("flag", {}))
		top.add_child(flag)
		var nm := UIStyle.label(GameData.nation_name(nid), 15, UIStyle.ACCENT)
		top.add_child(nm)
		v.add_child(top)
		var st := UIStyle.label("", 13, UIStyle.TEXT)
		st.name = "Status"
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size.x = UIStyle.RIGHT_PANEL_WIDTH - 80
		v.add_child(st)
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 4)
		var r := {"row": box, "flag": flag, "name": nm, "status": st}
		for key in ["justify", "declare", "pact", "access"]:
			var b := Button.new()
			b.name = key.capitalize()
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 12)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(_on_pressed.bind(key, nid))
			btns.add_child(b)
			r[key] = b
		v.add_child(btns)
		list.add_child(box)
		rows[nid] = r


func _on_pressed(key: String, target: String) -> void:
	var dp := _dip()
	var pid := _player()
	if dp == null or pid == "":
		return
	match key:
		"justify":
			if dp.war_goal_days_left(pid, target) >= 0:
				dp.cancel_justification(pid, target)
			else:
				dp.start_justification(pid, target)
		"declare":
			dp.declare_war(pid, target)
		"pact":
			if dp.has_pact(pid, target):
				dp.cancel_pact(pid, target)
			else:
				dp.offer_pact(pid, target)
		"access":
			dp.request_access(pid, target)
	refresh()


func _apply_button(b: Button, text: String, err: String, ok_tip: String) -> void:
	b.text = text
	b.disabled = err != ""
	b.tooltip_text = err if err != "" else ok_tip


func refresh() -> void:
	_dirty = false
	var pid := _player()
	if pid != _built_for:
		_rebuild_rows(pid)
	var dp := _dip()
	if pid == "" or dp == null:
		summary.text = "No game running"
		return
	var en: PackedStringArray = []
	for e in dp.enemies(pid):
		en.append(GameData.nation_name(e))
	summary.text = "At war with: " + (", ".join(en) if not en.is_empty() else "nobody")
	summary.add_theme_color_override("font_color", UIStyle.BAD if not en.is_empty() else UIStyle.GOOD)
	for nid in rows:
		var r: Dictionary = rows[nid]
		var st: Label = r.status
		st.text = dp.status_text(pid, nid)
		var col := UIStyle.TEXT
		if dp.is_at_war(pid, nid):
			col = UIStyle.BAD
		elif dp.has_pact(pid, nid):
			col = UIStyle.GOOD
		st.add_theme_color_override("font_color", col)
		var left: int = dp.war_goal_days_left(pid, nid)
		if left >= 0:
			_apply_button(r.justify, "Cancel", "", "Drop the war goal against %s" % GameData.nation_name(nid))
		else:
			_apply_button(r.justify, "Justify", dp.justification_error(pid, nid),
				"Fabricate a war goal (%d days)" % _goal_days())
		_apply_button(r.declare, "Declare war", dp.declare_war_error(pid, nid), "Declare war on %s" % GameData.nation_name(nid))
		if dp.has_pact(pid, nid):
			_apply_button(r.pact, "Break pact", "", "Cancel the non-aggression pact")
		else:
			_apply_button(r.pact, "Offer pact", dp.pact_error(pid, nid), "Offer a non-aggression pact")
		_apply_button(r.access, "Request access", dp.access_error(pid, nid),
			"Ask for military access through %s" % GameData.nation_name(nid))
