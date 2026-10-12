class_name TopBar
extends PanelContainer
## Top bar: player flag + nation name, current date, speed controls and
## resource counts (manpower, oil, steel, factories).
##
## Speed controls talk to the TimeManager autoload when it exists (step 5):
##   TimeManager.toggle_pause() / TimeManager.set_speed(index)
## and mirror EventBus.speed_changed(speed_index, paused). Without a
## TimeManager they only keep local state.

const RESOURCES: PackedStringArray = ["manpower", "oil", "steel", "factories"]
const RESOURCE_TITLES := {
	"manpower": "Manpower", "oil": "Oil", "steel": "Steel", "factories": "Factories",
}
const RESOURCE_TIPS := {
	"manpower": "Manpower pool: men available to recruit new divisions.",
	"oil": "Oil stockpile: needed to produce armor.",
	"steel": "Steel stockpile: needed for all equipment and new factories.",
	"factories": "Factories in provinces you control: they decide production speed.",
}

var flag_view: FlagView
var nation_label: Label
var date_label: Label
var time_label: Label
var pause_button: Button
var speed_buttons: Array[Button] = []
## resource id -> value Label
var resource_labels: Dictionary = {}

var paused: bool = true
var speed_index: int = 0


func _ready() -> void:
	name = "TopBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = UIStyle.TOP_BAR_HEIGHT
	add_theme_stylebox_override("panel", _bar_style())
	_build()
	EventBus.game_state_ready.connect(refresh)
	EventBus.day_passed.connect(func(_d: int) -> void: refresh())
	EventBus.hour_passed.connect(func(_h: int) -> void: refresh_date())
	EventBus.nation_changed.connect(_on_nation_changed)
	EventBus.province_changed.connect(func(_p: String) -> void: refresh_resources())
	EventBus.speed_changed.connect(_on_speed_changed)
	refresh()


func _bar_style() -> StyleBoxFlat:
	var sb := UIStyle.flat_box(Color(0.07, 0.075, 0.09, 0.97), 0, 6)
	sb.border_color = UIStyle.PANEL_BORDER
	sb.border_width_bottom = 2
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _build() -> void:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	# Nation
	flag_view = FlagView.new()
	flag_view.name = "Flag"
	flag_view.custom_minimum_size = Vector2(60, 40)
	flag_view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(flag_view)
	nation_label = UIStyle.label("", 22, UIStyle.TEXT)
	nation_label.name = "NationName"
	nation_label.custom_minimum_size.x = 190
	row.add_child(nation_label)
	row.add_child(VSeparator.new())

	# Date + speed
	var date_box := VBoxContainer.new()
	date_box.add_theme_constant_override("separation", -4)
	date_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(date_box)
	date_label = UIStyle.label("", 20, UIStyle.ACCENT)
	date_label.name = "Date"
	date_label.custom_minimum_size.x = 190
	date_box.add_child(date_label)
	time_label = UIStyle.label("", 13, UIStyle.TEXT_DIM)
	time_label.name = "Time"
	date_box.add_child(time_label)

	var speed_box := HBoxContainer.new()
	speed_box.name = "Speed"
	speed_box.add_theme_constant_override("separation", 4)
	speed_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(speed_box)
	pause_button = Button.new()
	pause_button.name = "Pause"
	pause_button.custom_minimum_size = Vector2(70, 34)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.tooltip_text = "Pause / resume the game clock"
	pause_button.pressed.connect(_on_pause_pressed)
	speed_box.add_child(pause_button)
	var speeds: Array = GameData.rule("speeds", [1, 2, 3, 5])
	for i in speeds.size():
		var b := Button.new()
		b.name = "Speed%d" % (i + 1)
		b.text = str(i + 1)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 34)
		b.tooltip_text = "Speed %d (%sx)" % [i + 1, str(speeds[i])]
		b.pressed.connect(_on_speed_pressed.bind(i))
		speed_box.add_child(b)
		speed_buttons.append(b)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	# Resources
	for rid in RESOURCES:
		var box := HBoxContainer.new()
		box.name = "Res_" + rid
		box.add_theme_constant_override("separation", 6)
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.tooltip_text = RESOURCE_TIPS[rid]
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon := ResourceIcon.new(rid)
		box.add_child(icon)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", -5)
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(UIStyle.label(RESOURCE_TITLES[rid], 11, UIStyle.TEXT_DIM))
		var val := UIStyle.label("0", 18, UIStyle.TEXT)
		val.name = "Value"
		val.custom_minimum_size.x = 78
		texts.add_child(val)
		box.add_child(texts)
		row.add_child(box)
		resource_labels[rid] = val
	_update_speed_buttons()


func refresh() -> void:
	refresh_nation()
	refresh_date()
	refresh_resources()


func refresh_nation() -> void:
	var nid: String = GameState.player_nation
	flag_view.set_flag(GameData.nation(nid).get("flag", {}))
	nation_label.text = GameData.nation_name(nid) if nid != "" else "-"


func refresh_date() -> void:
	if not GameState.active:
		date_label.text = "-"
		time_label.text = ""
		return
	date_label.text = GameState.date_string()
	time_label.text = "%02d:00" % GameState.hour


func refresh_resources() -> void:
	var n: NationState = GameState.player() if GameState.active else null
	if n == null:
		for rid in resource_labels:
			resource_labels[rid].text = "-"
		return
	resource_labels["manpower"].text = UIStyle.fmt_compact(n.manpower)
	resource_labels["oil"].text = UIStyle.fmt_int(float(n.stockpile.get("oil", 0.0)))
	resource_labels["steel"].text = UIStyle.fmt_int(float(n.stockpile.get("steel", 0.0)))
	resource_labels["factories"].text = str(GameState.factory_count(n.id))


## Current text of a resource counter (used by tests).
func resource_text(rid: String) -> String:
	return resource_labels[rid].text if resource_labels.has(rid) else ""


func _on_nation_changed(nid: String) -> void:
	if nid == GameState.player_nation:
		refresh_resources()


# --- Speed controls ----------------------------------------------------------

func _time_manager() -> Node:
	return get_node_or_null("/root/TimeManager")


func _on_pause_pressed() -> void:
	var tm := _time_manager()
	if tm and tm.has_method("toggle_pause"):
		tm.toggle_pause()   # TimeManager emits speed_changed -> _on_speed_changed
	else:
		paused = not paused
		_update_speed_buttons()


func _on_speed_pressed(index: int) -> void:
	var tm := _time_manager()
	if tm and tm.has_method("set_speed"):
		tm.set_speed(index)
	else:
		speed_index = index
	_update_speed_buttons()


func _on_speed_changed(index: int, is_paused: bool) -> void:
	speed_index = index
	paused = is_paused
	_update_speed_buttons()


func _update_speed_buttons() -> void:
	pause_button.text = "PLAY" if paused else "PAUSE"
	pause_button.add_theme_color_override("font_color", UIStyle.BAD if paused else UIStyle.TEXT)
	for i in speed_buttons.size():
		speed_buttons[i].set_pressed_no_signal(i == speed_index)


# --- Resource icon -------------------------------------------------------------

class ResourceIcon extends Control:
	var kind: String

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		match kind:
			"manpower":
				var col := Color(0.85, 0.8, 0.65)
				draw_circle(c + Vector2(0, -6), 5.0, col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-9, 11), c + Vector2(-7, 1), c + Vector2(0, -1), c + Vector2(7, 1), c + Vector2(9, 11)
				]), col)
			"oil":
				var col := Color(0.2, 0.2, 0.22)
				draw_circle(c + Vector2(0, 4), 7.0, col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -11), c + Vector2(6.6, 1.6), c + Vector2(-6.6, 1.6)
				]), col)
				draw_circle(c + Vector2(-2.5, 4), 2.0, Color(0.6, 0.6, 0.65))
			"steel":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-11, 7), c + Vector2(11, 7), c + Vector2(7, -5), c + Vector2(-7, -5)
				]), Color(0.62, 0.68, 0.75))
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-7, -5), c + Vector2(7, -5), c + Vector2(5, -8), c + Vector2(-5, -8)
				]), Color(0.82, 0.86, 0.9))
			"factories":
				var col := Color(0.75, 0.55, 0.35)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-11, 11), c + Vector2(-11, -1), c + Vector2(-5, -5), c + Vector2(-5, -1),
					c + Vector2(1, -5), c + Vector2(1, -1), c + Vector2(6, -4), c + Vector2(6, -11),
					c + Vector2(10, -11), c + Vector2(10, 11)
				]), col)
