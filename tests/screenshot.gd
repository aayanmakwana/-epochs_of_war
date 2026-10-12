extends SceneTree
## Dev helper (not a test): renders the main scene in a real window and saves
## a PNG.  godot --path . -s res://tests/screenshot.gd -- --out=C:/tmp/shot.png [--select=berlin] [--days=40]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://screenshot.png"
	var select := ""
	var days := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--select="):
			select = arg.trim_prefix("--select=")
		elif arg.begins_with("--days="):
			days = int(arg.trim_prefix("--days="))
	root.size = Vector2i(1920, 1080)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var game: Node = main.current_screen
	if select != "" and game.get("map_view"):
		game.map_view.select_province(select)
	var tm: Node = root.get_node_or_null("/root/TimeManager")
	if days > 0 and tm:
		tm.advance_days(days)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit(0)
