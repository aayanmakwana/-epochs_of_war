extends "res://tests/test_base.gd"
## Step 2: data layer. JSON definitions, map geometry, GameState, save dict.

const EXPECTED_PROVINCES := ["berlin", "east_prussia", "poland", "romania", "hungary",
	"czechoslovakia", "austria", "western_germany", "france", "moscow", "leningrad",
	"stalingrad", "ukraine", "belarus", "caucasus", "urals", "siberia", "london",
	"north_sea", "mediterranean"]


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var gs: Node = autoload("GameState")
	check(gd != null and gs != null, "GameData and GameState autoloads present")
	check(gd.errors.is_empty(), "data loads without errors: " + ", ".join(gd.errors))

	# Provinces
	check_eq(gd.province_ids.size(), 20, "20 provinces")
	check_eq(Array(gd.province_ids), EXPECTED_PROVINCES, "province order matches design doc")
	var terrains := {}
	for pid in gd.province_ids:
		var p: Dictionary = gd.provinces[pid]
		terrains[p.terrain] = true
		for key in ["name", "terrain", "owner", "infrastructure", "factories", "resources"]:
			check(p.has(key), "province %s has %s" % [pid, key])
	check_eq(terrains.size(), 6, "all 6 terrain types used")
	check_eq(Array(gd.major_cities()), ["berlin", "moscow", "leningrad", "stalingrad", "london"], "5 major cities")
	check(gd.is_naval("north_sea") and gd.is_naval("mediterranean") and not gd.is_naval("berlin"), "naval zones flagged")
	check(gd.province("romania").resources.oil > 0 and gd.province("caucasus").resources.oil > 0, "oil in Romania and Caucasus")
	check(gd.province("ukraine").resources.food > 0, "food in Ukraine")

	# Nations
	check_eq(Array(gd.playable_nations()), ["germany", "ussr", "uk"], "3 playable nations")
	check_eq(gd.nation("germany").capital, "berlin", "German capital")
	check_eq(gd.nation("ussr").capital, "moscow", "Soviet capital")
	check_eq(gd.nation("uk").capital, "london", "British capital")
	check_eq(gd.province("france").owner, "france", "France starts as its own (neutral) nation")
	check(gd.nation("ussr").manpower > gd.nation("germany").manpower, "USSR has the largest manpower")

	# Map geometry
	var geo: MapGeometry = gd.geometry
	check(geo.errors.is_empty(), "geometry builds cleanly: " + ", ".join(geo.errors))
	for pid in gd.province_ids:
		check_eq(geo.outlines.get(pid, []).size(), 1, "one outline loop for " + pid)
		var adj: PackedStringArray = gd.adjacent(pid)
		check(adj.size() > 0, "%s has neighbours" % pid)
		for other in adj:
			check(gd.adjacent(other).has(pid), "adjacency symmetric %s-%s" % [pid, other])
		check_eq(geo.province_at(geo.anchors[pid]), pid, "anchor of %s lies inside it" % pid)
	for pair in [["berlin", "poland"], ["berlin", "western_germany"], ["london", "north_sea"],
			["moscow", "leningrad"], ["ukraine", "romania"], ["france", "western_germany"],
			["caucasus", "stalingrad"], ["east_prussia", "poland"]]:
		check(gd.are_adjacent(pair[0], pair[1]), "%s adjacent to %s" % pair)
	for pair in [["london", "france"], ["berlin", "moscow"], ["london", "berlin"]]:
		check(not gd.are_adjacent(pair[0], pair[1]), "%s NOT adjacent to %s" % pair)
	# All provinces connected (BFS over adjacency).
	var seen := {"berlin": true}
	var queue: Array = ["berlin"]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in gd.adjacent(cur):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	check_eq(seen.size(), 20, "map graph connected")
	# Deterministic geometry.
	var geo2 := MapGeometry.new()
	geo2.build(gd.map_def)
	check(geo2.outlines["berlin"][0] == geo.outlines["berlin"][0], "geometry deterministic")

	# Divisions / equipment / techs / tactical
	check_eq(Array(gd.division_ids), ["infantry", "armor", "artillery"], "3 division templates")
	for did in gd.division_ids:
		for stat in ["attack", "defense", "speed", "organization", "hp", "manpower", "equipment"]:
			check(gd.divisions[did].has(stat), "division %s has %s" % [did, stat])
	check_eq(Array(gd.equipment_ids), ["infantry_equipment", "armor", "artillery"], "3 equipment types")
	check_eq(gd.tech_ids.size(), 15, "15 techs")
	for branch in ["infantry", "armor", "doctrine"]:
		var list: PackedStringArray = gd.techs_in_branch(branch)
		check_eq(list.size(), 5, "5 techs in " + branch)
		for i in list.size():
			var t: Dictionary = gd.techs[list[i]]
			check(int(t.days) >= 30 and int(t.days) <= 90, "tech %s takes 30-90 days" % t.id)
			check_eq(t.requires, "" if i == 0 else list[i - 1], "tech %s prerequisite chain" % t.id)
	check_eq(Array(gd.techs_in_branch("infantry")), ["basic_infantry", "improved_infantry", "elite_infantry", "mechanized_infantry", "special_forces"], "infantry branch order")
	check_eq(int(gd.tactical.grid_size), 20, "tactical grid 20x20")
	check_eq(gd.tactical.units.infantry.hp, 10, "tactical infantry hp from spec")

	# Tech effects (loaded at runtime: scripts that use autoload names cannot be
	# referenced statically from a -s test script, see PROGRESS.md)
	var TE: GDScript = load("res://scripts/core/tech_effects.gd")
	var base: Dictionary = TE.division_stats("infantry", [])
	var boosted: Dictionary = TE.division_stats("infantry", ["basic_infantry"])
	check(is_equal_approx(boosted.defense, base.defense * 1.1), "basic_infantry gives +10% infantry defense")
	check(not TE.is_division_unlocked("armor", []), "armor locked without light_tanks")
	check(TE.is_division_unlocked("armor", ["light_tanks"]), "light_tanks unlocks armor")
	check(TE.can_research("improved_infantry", ["basic_infantry"]), "can research tier 2 after tier 1")
	check(not TE.can_research("heavy_tanks", ["light_tanks"]), "cannot skip tiers")

	# Dates
	check_eq(GameDate.format(0), "1 January 1936", "day 0 is 1 January 1936")
	check_eq(GameDate.format(31), "1 February 1936", "day 31 is 1 February")
	check_eq(GameDate.format(366), "1 January 1937", "1936 is a leap year")
	check_eq(GameDate.to_index(1945, 5, 8), GameDate.to_index(1945, 5, 8), "to_index stable")
	var idx := GameDate.to_index(1941, 6, 22)
	var back := GameDate.from_index(idx)
	check(back.year == 1941 and back.month == 6 and back.day == 22, "date round trip 22 June 1941")

	# GameState
	gs.new_game("germany")
	check(gs.active, "new game active")
	check_eq(gs.day_index, 0, "game starts 1 Jan 1936")
	check_eq(gs.provinces.size(), 20, "20 province states")
	check_eq(gs.nations.size(), gd.nation_ids.size(), "nation states for every nation")
	check(gs.player().is_player and gs.player().id == "germany", "player nation flagged")
	check_eq(gs.factory_count("germany"), 17, "German factories = sum of provinces")
	check(gs.divisions_of("germany").size() == 5, "German starting divisions spawned")
	check(gs.divisions_in("london").size() == 3, "British divisions in London")

	# Save dict round trip through JSON text
	gs.province("poland").controller = "germany"
	gs.nation("germany").stockpile.oil = 123.5
	gs.nation("germany").current_research = "improved_infantry"
	var before: Dictionary = gs.to_dict()
	var text := JSON.stringify(before)
	var parsed: Dictionary = JSON.parse_string(text)
	check(gs.load_from_dict(parsed), "load_from_dict accepts JSON round-tripped state")
	check_eq(gs.province("poland").controller, "germany", "controller survives round trip")
	check_eq(gs.nation("germany").stockpile.oil, 123.5, "stockpile survives round trip")
	check_eq(gs.nation("germany").current_research, "improved_infantry", "research survives round trip")
	check_eq(gs.divisions.size(), before.divisions.size(), "divisions survive round trip")
	check_eq(JSON.stringify(gs.to_dict()), text, "to_dict identical after round trip")
	check(not gs.load_from_dict({}), "load_from_dict rejects garbage")
