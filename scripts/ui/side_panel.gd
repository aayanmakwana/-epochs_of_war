class_name SidePanel
extends PanelContainer
## Right panel with tabs: Production, Research, Diplomacy.
## Step 4 ships them empty (placeholder text). Later steps fill a tab with:
##   var box: VBoxContainer = hud.side_panel.tab_content("Production")
##   box.add_child(...)   # call clear_tab("Production") first to drop the placeholder
## The panel can be collapsed to its header with the "-" button.

signal tab_changed(tab_name: String)

const TABS: PackedStringArray = ["Production", "Research", "Diplomacy"]
const PLACEHOLDERS := {
	"Production": "Assign factories to equipment, see output per day and build new factories.\n\n(Coming in step 6.)",
	"Research": "Pick one of 15 technologies in the Infantry, Armor and Doctrine branches.\n\n(Coming in step 7.)",
	"Diplomacy": "Declare war, offer non-aggression pacts and request military access.\n\n(Coming in step 13.)",
}

var tabs: TabContainer
var collapse_button: Button
var collapsed: bool = false
## tab name -> VBoxContainer
var _contents: Dictionary = {}
var _body: VBoxContainer


func _ready() -> void:
	name = "SidePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_apply_rect()
	_build()
	get_viewport().size_changed.connect(_apply_rect)


func _apply_rect() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -UIStyle.RIGHT_PANEL_WIDTH - UIStyle.MARGIN
	offset_right = -UIStyle.MARGIN
	offset_top = UIStyle.TOP_BAR_HEIGHT + UIStyle.MARGIN
	# Leave room for the minimap underneath.
	offset_bottom = -(minimap_height() + UIStyle.MARGIN * 2)
	if collapsed:
		offset_bottom = offset_top + 52 - get_viewport_rect().size.y


static func minimap_height() -> float:
	return UIStyle.MINIMAP_WIDTH * 0.62 + 20


func _build() -> void:
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 6)
	add_child(_body)

	var header := HBoxContainer.new()
	header.name = "Header"
	var title := UIStyle.label("Command", 18, UIStyle.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	collapse_button = Button.new()
	collapse_button.name = "Collapse"
	collapse_button.text = "-"
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.custom_minimum_size = Vector2(30, 28)
	collapse_button.tooltip_text = "Collapse / expand"
	collapse_button.pressed.connect(func() -> void: set_collapsed(not collapsed))
	header.add_child(collapse_button)
	_body.add_child(header)

	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	_body.add_child(tabs)
	for tab_name in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.name = "Content"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		scroll.add_child(box)
		tabs.add_child(scroll)
		_contents[tab_name] = box
		var ph := UIStyle.label(PLACEHOLDERS[tab_name], 15, UIStyle.TEXT_DIM)
		ph.name = "Placeholder"
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.custom_minimum_size.x = UIStyle.RIGHT_PANEL_WIDTH - 60
		box.add_child(ph)
	tabs.tab_changed.connect(func(i: int) -> void: tab_changed.emit(TABS[i]))


## Content container of a tab (VBoxContainer inside a ScrollContainer).
func tab_content(tab_name: String) -> VBoxContainer:
	return _contents.get(tab_name)


## Remove everything (including the placeholder) from a tab.
func clear_tab(tab_name: String) -> void:
	var box: VBoxContainer = _contents.get(tab_name)
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func select_tab(tab_name: String) -> void:
	var i := TABS.find(tab_name)
	if i >= 0:
		tabs.current_tab = i
		if collapsed:
			set_collapsed(false)


func current_tab_name() -> String:
	return TABS[tabs.current_tab]


func set_collapsed(value: bool) -> void:
	collapsed = value
	tabs.visible = not collapsed
	collapse_button.text = "+" if collapsed else "-"
	_apply_rect()
