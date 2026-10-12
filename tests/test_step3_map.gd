extends "res://tests/test_base.gd"
## Step 3: strategic map rendering. Polygons, colours, borders, selection, zoom/pan.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	gs.new_game("germany")

	var packed: PackedScene = load("res://scenes/game/game.tscn")
	check(packed != null, "game scene loads")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var map = game.map_view
	var cam = game.camera
	check(map != null and cam != null, "MapView and MapCamera exist")

	# Polygons
	check_eq(map.fill_nodes.size(), 20, "20 province fills")
	for pid in gd.province_ids:
		var polys: Array = map.fill_nodes[pid]
		check(polys.size() == 1 and polys[0].polygon.size() >= 8, "polygon for " + pid)
		check(map.label_nodes.has(pid) and map.label_nodes[pid].text == gd.province_name(pid), "label for " + pid)
	for layer in ["Fills", "Borders", "Fronts", "Highlight", "Units", "Labels", "Fog"]:
		check(map.layers.has(layer), "layer " + layer)

	# Nation colours
	var berlin_col: Color = map.fill_nodes["berlin"][0].color
	var moscow_col: Color = map.fill_nodes["moscow"][0].color
	check(berlin_col == map.province_color("berlin"), "berlin filled with its province colour")
	check(not berlin_col.is_equal_approx(moscow_col), "German and Soviet colours differ")
	var sea_col: Color = map.fill_nodes["north_sea"][0].color
	check(sea_col.b > sea_col.r, "naval zone drawn blue")
	check(gd.geometry.borders.has("berlin|poland"), "border segments between Berlin and Poland")
	check(gd.geometry.borders.has("london|"), "coastline segments for London")

	# Recolour when controller changes
	gs.province("poland").controller = "germany"
	bus.province_changed.emit("poland")
	check(map.fill_nodes["poland"][0].color.is_equal_approx(map.province_color("poland")), "poland recoloured")
	var g: Color = gd.nation_color("germany")
	var pc: Color = map.fill_nodes["poland"][0].color
	check(absf(pc.r - g.lerp(Color.from_string("#b5c27a", Color.GRAY), 0.18).r) < 0.01, "poland now in German colour")

	# Selection
	var selected: Array = []
	var cleared: Array = []
	bus.province_selected.connect(func(p): selected.append(p))
	bus.selection_cleared.connect(func(): cleared.append(true))
	for pid in gd.province_ids:
		check_eq(map.click_at(gd.geometry.anchors[pid]), pid, "click on anchor selects " + pid)
	check_eq(selected.size(), 20, "province_selected emitted for every click")
	check_eq(map.selected_province, "mediterranean", "last selection kept")
	check_eq(map.click_at(Vector2(-400, -400)), "", "click off-map selects nothing")
	check_eq(map.selected_province, "", "off-map click clears selection")
	check_eq(cleared.size(), 1, "selection_cleared emitted")
	# Points just inside the jittered border resolve to a province (no holes).
	var holes := 0
	var b: Rect2 = gd.geometry.bounds()
	for y in range(5, int(b.size.y), 23):
		for x in range(5, int(b.size.x), 23):
			var c := Vector2i(floori(x / 50.0), floori(y / 50.0))
			var interior := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if gd.geometry.cell_at(c + Vector2i(dx, dy)) == "":
						interior = false
			if interior and map.province_at(Vector2(x, y)) == "":
				holes += 1
	check_eq(holes, 0, "no holes between province polygons")

	# Zoom and pan
	cam.set_zoom_level(100.0)
	check_eq(cam.zoom_level(), cam.max_zoom, "zoom clamped to max")
	cam.set_zoom_level(0.001)
	check_eq(cam.zoom_level(), cam.min_zoom, "zoom clamped to min")
	cam.set_zoom_level(1.0)
	var before: Vector2 = cam.position
	cam.pan_by(Vector2(120, 0))
	check(cam.position.x > before.x, "pan moves camera")
	cam.pan_by(Vector2(100000, 100000))
	check(b.grow(101).has_point(cam.position), "pan clamped to map bounds")
	cam.focus_on(gd.geometry.anchors["moscow"])
	check(cam.visible_world_rect().has_point(gd.geometry.anchors["moscow"]), "focus_on centres province")
	# Zoom keeps the point under the cursor fixed.
	cam.set_zoom_level(1.0)
	cam.focus_on(b.get_center())
	var vp: Vector2 = cam.get_viewport_rect().size
	var anchor_px := vp * 0.5 + Vector2(200, 100)
	var world_before: Vector2 = cam.position + (anchor_px - vp * 0.5) / cam.zoom_level()
	cam.set_zoom_level(2.0, anchor_px)
	var world_after: Vector2 = cam.position + (anchor_px - vp * 0.5) / cam.zoom_level()
	check(world_before.distance_to(world_after) < 0.5, "zoom towards cursor keeps world point fixed")

	# Rebuild keeps node names and counts stable.
	map.build()
	check_eq(map.fill_nodes.size(), 20, "rebuild: 20 province fills")
	check(map.get_node_or_null("Fills") != null and map.get_node_or_null("Borders") != null, "rebuild: layer names kept")
	check_eq(map.get_child_count(), 7, "rebuild: no stale layers left")

	game.queue_free()
	await process_frame
