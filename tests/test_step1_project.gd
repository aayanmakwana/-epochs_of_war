extends "res://tests/test_base.gd"
## Step 1: project setup. Settings, folders, main scene, autoloads.
## Updated in step 19: main scene is now start_screen.tscn; Main is an autoload.


func run_tests() -> void:
	check_eq(ProjectSettings.get_setting("application/config/name"), "Epochs of War", "project name")
	check_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/start_screen.tscn", "main scene path")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1920, "viewport width 1920")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1080, "viewport height 1080")
	check_eq(ProjectSettings.get_setting("display/window/size/mode"), 0, "windowed mode")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	var ver: Dictionary = Engine.get_version_info()
	check(features.has("%d.%d" % [ver.major, ver.minor]), "config/features matches engine version %d.%d" % [ver.major, ver.minor])

	for dir in ["res://scenes", "res://scripts", "res://data", "res://assets", "res://tests"]:
		check(DirAccess.dir_exists_absolute(dir), "folder exists: " + dir)

	check(autoload("EventBus") != null, "EventBus autoload present")

	# Step 19: main scene is the start screen; Main is an autoload.
	var packed: PackedScene = load("res://scenes/start_screen.tscn")
	check(packed != null, "start_screen scene loads")
	if packed:
		var screen: Node = packed.instantiate()
		check(screen != null, "start_screen scene instantiates")
		root.add_child(screen)
		await process_frame
		screen.queue_free()
		await process_frame

	# Main autoload exists and has screen-switching methods.
	var main: Node = autoload("Main")
	check(main != null, "Main autoload present")
	if main:
		check(main.has_method("show_start_screen"), "Main has show_start_screen")
		check(main.has_method("start_game_screen"), "Main has start_game_screen")
		check(main.has_method("show_end_screen"), "Main has show_end_screen")
