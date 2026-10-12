extends "res://tests/test_base.gd"
## Step 1: project setup. Settings, folders, main scene, autoloads.


func run_tests() -> void:
	check_eq(ProjectSettings.get_setting("application/config/name"), "Epochs of War", "project name")
	check_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/main.tscn", "main scene path")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1920, "viewport width 1920")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1080, "viewport height 1080")
	check_eq(ProjectSettings.get_setting("display/window/size/mode"), 0, "windowed mode")
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features")
	var ver: Dictionary = Engine.get_version_info()
	check(features.has("%d.%d" % [ver.major, ver.minor]), "config/features matches engine version %d.%d" % [ver.major, ver.minor])

	for dir in ["res://scenes", "res://scripts", "res://data", "res://assets", "res://tests"]:
		check(DirAccess.dir_exists_absolute(dir), "folder exists: " + dir)

	check(autoload("EventBus") != null, "EventBus autoload present")

	var packed: PackedScene = load("res://scenes/main.tscn")
	check(packed != null, "main scene loads")
	if packed:
		var main: Node = packed.instantiate()
		check(main != null, "main scene instantiates")
		root.add_child(main)
		await process_frame
		check(main.current_screen != null, "main scene shows a screen")
		main.queue_free()
		await process_frame
