class_name UIStyle
extends RefCounted
## Shared look of the HUD: colours, panel style boxes and the HUD Theme.
## Pure helper (no autoload references) so tests may use it directly.

const PANEL_BG := Color(0.09, 0.1, 0.12, 0.93)
const PANEL_BORDER := Color(0.55, 0.47, 0.3, 0.9)
const HEADER_BG := Color(0.14, 0.15, 0.18, 1.0)
const TEXT := Color(0.92, 0.9, 0.84)
const TEXT_DIM := Color(0.65, 0.64, 0.6)
const ACCENT := Color(0.95, 0.78, 0.35)
const GOOD := Color(0.55, 0.85, 0.5)
const BAD := Color(0.95, 0.45, 0.4)

const TOP_BAR_HEIGHT := 56
const MARGIN := 8
const LEFT_PANEL_WIDTH := 360
const RIGHT_PANEL_WIDTH := 430
const MINIMAP_WIDTH := 340


static func panel_box(bg: Color = PANEL_BG, border: int = 2, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	return sb


static func flat_box(bg: Color, radius: int = 4, margin: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	var normal := flat_box(Color(0.2, 0.21, 0.25), 4, 6)
	var hover := flat_box(Color(0.28, 0.29, 0.34), 4, 6)
	var pressed := flat_box(Color(0.45, 0.37, 0.18), 4, 6)
	var disabled := flat_box(Color(0.15, 0.15, 0.17), 4, 6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_stylebox("panel", "TabContainer", flat_box(Color(0.11, 0.12, 0.14, 1.0), 4, 8))
	t.set_stylebox("tab_selected", "TabContainer", flat_box(Color(0.45, 0.37, 0.18), 4, 8))
	t.set_stylebox("tab_unselected", "TabContainer", flat_box(Color(0.18, 0.19, 0.22), 4, 8))
	t.set_stylebox("tab_hovered", "TabContainer", flat_box(Color(0.26, 0.27, 0.31), 4, 8))
	t.set_color("font_selected_color", "TabContainer", Color(1, 0.95, 0.8))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	return t


static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func section_header(text: String) -> Label:
	var l := label(text.to_upper(), 13, ACCENT)
	return l


## Thousands separators: 1234567 -> "1,234,567".
static func fmt_int(v: float) -> String:
	var n := int(round(v))
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	out = s + out
	return ("-" if neg else "") + out


## Compact: 2500000 -> "2.50M", 12345 -> "12.3K", 950 -> "950".
static func fmt_compact(v: float) -> String:
	var a := absf(v)
	if a >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if a >= 10000.0:
		return "%.1fK" % (v / 1000.0)
	return fmt_int(v)
