class_name Hud
extends Control
## In-game HUD root (full screen, ignores the mouse itself so map clicks pass
## through). Children: TopBar, InfoPanel (left), SidePanel (right, tabbed),
## Minimap (bottom right). game.gd calls setup(map_view, camera).

var top_bar: TopBar
var info_panel: InfoPanel
var side_panel: SidePanel
var production_panel: ProductionPanel
var research_panel: ResearchPanel
var recruit_panel: RecruitPanel
var diplomacy_panel: DiplomacyPanel
var minimap: Minimap
var map_view: MapView


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIStyle.make_theme()
	info_panel = InfoPanel.new()
	add_child(info_panel)
	side_panel = SidePanel.new()
	add_child(side_panel)
	side_panel.clear_tab("Production")
	production_panel = ProductionPanel.new()
	side_panel.tab_content("Production").add_child(production_panel)
	recruit_panel = RecruitPanel.new()
	side_panel.tab_content("Production").add_child(recruit_panel)
	side_panel.clear_tab("Research")
	research_panel = ResearchPanel.new()
	side_panel.tab_content("Research").add_child(research_panel)
	side_panel.clear_tab("Diplomacy")
	diplomacy_panel = DiplomacyPanel.new()
	side_panel.tab_content("Diplomacy").add_child(diplomacy_panel)
	minimap = Minimap.new()
	add_child(minimap)
	top_bar = TopBar.new()
	add_child(top_bar)
	for panel: Control in [info_panel, side_panel, minimap, top_bar]:
		panel.mouse_entered.connect(_on_panel_entered)


func setup(view: MapView, cam: MapCamera) -> void:
	map_view = view
	minimap.setup(view, cam)


func _on_panel_entered() -> void:
	# The map does not see mouse motion over panels; drop its hover highlight.
	if map_view:
		map_view.set_hovered("")
