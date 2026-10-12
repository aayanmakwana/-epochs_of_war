class_name ResearchPanel
extends VBoxContainer
## Contents of the side panel's "Research" tab (step 7).
## Current research (name, progress bar, days left, stop button), the tech tree
## (GridContainer "TechGrid": one column per branch, 5 tier buttons each, coloured
## by status, description in the tooltip, thin progress bar under each) and the
## effective division template stats the techs produce.
## Talks to the Research autoload for the player nation.
##
## Built once and updated in place (refresh, at most once per frame).
## tech_cards[tid] = {"card", "button", "bar"}. Node names: Current (Row/Name,
## Row/Stop, Bar, Days), TechGrid/Branch_<branch>, TechGrid/Tech_<id> (Button, Bar),
## Templates/Template_<division>.

const STATUS_COLORS := {
	"researched": Color(0.16, 0.27, 0.17, 1.0),
	"researching": Color(0.38, 0.31, 0.14, 1.0),
	"available": Color(0.17, 0.18, 0.22, 1.0),
	"locked": Color(0.12, 0.12, 0.14, 1.0),
}

var current_name: Label
var current_bar: ProgressBar
var current_days: Label
var stop_button: Button
## branch -> Label (header with done/total)
var branch_labels: Dictionary = {}
## tech id -> {"card", "name", "status", "button", "bar"}
var tech_cards: Dictionary = {}
## template id -> Label
var template_labels: Dictionary = {}
var _dirty := true


func _ready() -> void:
	name = "ResearchPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build()
	EventBus.game_state_ready.connect(mark_dirty)
	EventBus.day_passed.connect(func(_d: int) -> void: mark_dirty())
	EventBus.nation_changed.connect(func(_n: String) -> void: mark_dirty())
	EventBus.research_started.connect(func(_n: String, _t: String) -> void: mark_dirty())
	EventBus.research_completed.connect(func(_n: String, _t: String) -> void: mark_dirty())
	refresh()


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		refresh()


func _research() -> Node:
	return get_node_or_null("/root/Research")


func _wrap(l: Label, width: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


func _build() -> void:
	var width := UIStyle.RIGHT_PANEL_WIDTH - 60
	add_child(UIStyle.section_header("Current research"))
	var cur := VBoxContainer.new()
	cur.name = "Current"
	cur.add_theme_constant_override("separation", 3)
	var row := HBoxContainer.new()
	row.name = "Row"
	current_name = UIStyle.label("", 16, UIStyle.ACCENT)
	current_name.name = "Name"
	current_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(current_name)
	stop_button = Button.new()
	stop_button.name = "Stop"
	stop_button.text = "Stop"
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.custom_minimum_size = Vector2(64, 26)
	stop_button.tooltip_text = "Pause this research (progress is kept)"
	stop_button.pressed.connect(_stop_pressed)
	row.add_child(stop_button)
	cur.add_child(row)
	current_bar = ProgressBar.new()
	current_bar.name = "Bar"
	current_bar.min_value = 0.0
	current_bar.max_value = 1.0
	current_bar.show_percentage = true
	current_bar.custom_minimum_size = Vector2(width, 18)
	cur.add_child(current_bar)
	current_days = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	current_days.name = "Days"
	cur.add_child(current_days)
	add_child(cur)
	# Tech tree: one column per branch, tiers top to bottom.
	add_child(UIStyle.section_header("Technologies"))
	var grid := GridContainer.new()
	grid.name = "TechGrid"
	grid.columns = maxi(1, GameData.tech_branches.size())
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	var col_w := floorf((width - 12.0) / float(grid.columns))
	var columns: Array = []
	var rows := 0
	for branch in GameData.tech_branches:
		var header := UIStyle.label(String(branch).to_upper(), 13, UIStyle.ACCENT)
		header.name = "Branch_" + branch
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.custom_minimum_size.x = col_w
		grid.add_child(header)
		branch_labels[branch] = header
		var list: Array = []
		for tid in GameData.techs_in_branch(branch):
			list.append(GameData.techs[tid].merged({"id": tid}))
		columns.append(list)
		rows = maxi(rows, list.size())
	for i in rows:
		for list: Array in columns:
			if i < list.size():
				grid.add_child(_build_card(list[i], col_w))
			else:
				grid.add_child(Control.new())

	add_child(UIStyle.section_header("Division templates"))
	var tbox := VBoxContainer.new()
	tbox.name = "Templates"
	tbox.add_theme_constant_override("separation", 2)
	for did in GameData.divisions:
		var l := _wrap(UIStyle.label("", 13), width)
		l.name = "Template_" + String(did)
		tbox.add_child(l)
		template_labels[did] = l
	add_child(tbox)


## One tech button (+ thin progress bar) for the tree grid. Description in the tooltip.
func _build_card(t: Dictionary, width: float) -> Control:
	var card := VBoxContainer.new()
	card.name = "Tech_" + String(t.id)
	card.add_theme_constant_override("separation", 1)
	var b := Button.new()
	b.name = "Button"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 54)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(_tech_pressed.bind(String(t.id)))
	card.add_child(b)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 5)
	card.add_child(bar)
	tech_cards[String(t.id)] = {"card": card, "button": b, "bar": bar}
	return card


func _tech_pressed(tid: String) -> void:
	var r := _research()
	if r and GameState.active:
		r.start_research(GameState.player_nation, tid)
	refresh()


func _stop_pressed() -> void:
	var r := _research()
	if r and GameState.active:
		r.cancel_research(GameState.player_nation)
	refresh()


func refresh() -> void:
	_dirty = false
	var r := _research()
	var active: bool = GameState.active and r != null and GameState.player() != null
	var nid: String = GameState.player_nation if active else ""
	var n: NationState = GameState.player() if active else null
	_refresh_current(r, nid, active)
	for branch in branch_labels:
		var txt := String(branch).to_upper()
		if active:
			var bp: Dictionary = r.branch_progress(nid, branch)
			txt += " %d/%d" % [int(bp.done), int(bp.total)]
		branch_labels[branch].text = txt
	for tid in tech_cards:
		_refresh_card(r, nid, active, tid)
	for did in template_labels:
		var l: Label = template_labels[did]
		var tpl: Dictionary = GameData.divisions[did]
		var nm := String(tpl.get("name", did))
		if not active:
			l.text = nm
			continue
		if not TechEffects.is_division_unlocked(did, n.researched):
			var req := String(tpl.get("required_tech", ""))
			l.text = "%s: locked (needs %s)" % [nm, r.tech_name(req)]
			l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
			continue
		var s: Dictionary = TechEffects.division_stats(did, n.researched)
		l.text = "%s: ATK %.1f  DEF %.1f  SPD %.1f  ORG %.0f  HP %.0f" % [nm,
			float(s.attack), float(s.defense), float(s.speed), float(s.organization), float(s.hp)]
		if float(s.support_attack_bonus) > 0.0:
			l.text += "  SUP +%d%%" % int(round(float(s.support_attack_bonus) * 100.0))
		l.add_theme_color_override("font_color", UIStyle.TEXT)


func _refresh_current(r: Node, nid: String, active: bool) -> void:
	var tid: String = r.current(nid) if active else ""
	stop_button.disabled = tid == ""
	if not active:
		current_name.text = "No game running"
		current_bar.value = 0.0
		current_days.text = ""
		return
	if tid == "":
		current_name.text = "Nothing researched"
		current_name.add_theme_color_override("font_color", UIStyle.BAD)
		current_bar.value = 0.0
		var avail: PackedStringArray = r.available_techs(nid)
		current_days.text = "Pick a technology below." if not avail.is_empty() else "All technologies researched."
		return
	current_name.text = r.tech_name(tid)
	current_name.add_theme_color_override("font_color", UIStyle.ACCENT)
	current_bar.value = r.progress_fraction(nid, tid)
	current_days.text = "%d / %d days, %d left" % [int(floor(r.progress_days(nid, tid) + 0.000001)),
		int(r.tech_days(tid)), r.days_left(nid, tid)]


func _set_button_color(b: Button, color: Color) -> void:
	for s in ["normal", "disabled"]:
		b.add_theme_stylebox_override(s, UIStyle.flat_box(color, 4, 4))
	b.add_theme_stylebox_override("hover", UIStyle.flat_box(color.lightened(0.15), 4, 4))


func _refresh_card(r: Node, nid: String, active: bool, tid: String) -> void:
	var c: Dictionary = tech_cards[tid]
	var b: Button = c.button
	var bar: ProgressBar = c.bar
	var t: Dictionary = GameData.techs[tid]
	var tname := String(t.get("name", tid))
	var days := int(t.get("days", 0))
	var desc := String(t.get("description", ""))
	if not active:
		b.text = "%s\n%d days" % [tname, days]
		b.disabled = true
		bar.value = 0.0
		return
	var st: String = r.status(nid, tid)
	_set_button_color(b, STATUS_COLORS.get(st, STATUS_COLORS.locked))
	bar.value = r.progress_fraction(nid, tid)
	var line := ""
	var tip := desc
	match st:
		"researched":
			line = "Done"
			b.disabled = true
		"researching":
			line = "%d days left" % r.days_left(nid, tid)
			b.disabled = true
			tip += "\nResearching now."
		_:
			var left: int = r.days_left(nid, tid)
			line = ("%d days" % days) if left >= days else ("%d / %d days" % [left, days])
			var err: String = r.research_error(nid, tid)
			b.disabled = err != ""
			if err != "":
				tip += "\n" + err
			elif r.current(nid) != "":
				tip += "\nClick to switch (progress on %s is kept)." % r.tech_name(r.current(nid))
			else:
				tip += "\nClick to research (%d days)." % days
	b.text = "%s\n%s" % [tname, line]
	b.tooltip_text = tip
