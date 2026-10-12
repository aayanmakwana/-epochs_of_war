extends "res://tests/test_base.gd"
## Step 11: supply. Provinces connected to the capital through friendly
## territory are in supply, cut-off provinces are not, military access extends
## supply, losing the capital cuts everything, out-of-supply divisions lose
## HP / organization daily, don't recover, die at 0 HP, notifications and
## supply_changed. (Untyped vars on purpose: see PROGRESS.md.)

var notes: Array = []
var changed: Array = []


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var sp: Node = autoload("Supply")
	check(sp != null, "Supply autoload present")
	if sp == null:
		return
	var daily: PackedStringArray = sim.daily_systems()
	check(daily.has("supply"), "supply daily system registered")
	check(daily.find("combat") < daily.find("supply") and daily.find("supply") < daily.find("combat_recovery"),
		"supply runs after combat, before recovery")
	bus.notify.connect(func(t: String) -> void: notes.append(t))
	bus.supply_changed.connect(func(n: String) -> void: changed.append(n))

	# --- Connected provinces in supply ---
	gs.new_game("germany")
	for nid in ["germany", "ussr", "poland", "france"]:
		check(sp.cut_off_provinces(nid).is_empty(), "%s: all controlled provinces in supply at start" % nid)
	# The Mediterranean touches neither London nor the North Sea (known limitation).
	check_eq(sp.cut_off_provinces("uk"), PackedStringArray(["mediterranean"]), "UK: only the detached Mediterranean is cut off")
	check_eq(sp.source("germany"), "berlin", "German supply source is Berlin")
	check(sp.is_province_supplied("germany", "east_prussia"), "East Prussia supplied via Berlin")
	check(sp.is_province_supplied("uk", "north_sea"), "UK North Sea supplied from London")
	check(not sp.is_province_supplied("germany", "poland"), "foreign Poland not German supply")

	# --- Cut-off province ---
	gs.province("moscow").controller = "germany"
	check(not sp.is_province_supplied("germany", "moscow"), "isolated German-held Moscow out of supply")
	check_eq(sp.cut_off_provinces("germany"), PackedStringArray(["moscow"]), "cut_off_provinces lists Moscow")
	check(not sp.is_province_supplied("ussr", "moscow"), "USSR has no supply without its capital")
	check(sp.supplied_provinces("ussr").is_empty(), "USSR supplied set empty after losing Moscow")
	gs.province("moscow").controller = "ussr"

	# --- Military access extends supply ---
	gs.province("ukraine").controller = "germany"
	check(not sp.is_province_supplied("germany", "ukraine"), "Ukraine cut off without access")
	gs.nation("germany").military_access.append("poland")
	check(sp.is_province_supplied("germany", "ukraine"), "access through Poland reconnects Ukraine")
	check(sp.is_province_supplied("germany", "poland"), "access province carries supply")
	gs.nation("germany").military_access.erase("poland")
	gs.province("ukraine").controller = "ussr"

	# --- Losing the capital ---
	gs.province("berlin").controller = "poland"
	check_eq(sp.source("germany"), "", "no source without Berlin")
	check(not sp.is_province_supplied("germany", "western_germany"), "Western Germany out of supply without Berlin")
	gs.province("berlin").controller = "germany"

	# --- Attrition ---
	gs.new_game("germany")
	gs.province("moscow").controller = "germany"
	var cut = gs.add_division("infantry", "germany", "moscow")
	var home = gs.add_division("infantry", "germany", "berlin")
	var max_hp: float = cut.hp
	var max_org: float = cut.organization
	check(not sp.is_supplied(cut) and sp.is_supplied(home), "is_supplied per division")
	check_eq(sp.out_of_supply_divisions("germany").size(), 1, "one German division out of supply")
	check(sp.status_text(cut).begins_with("OUT OF SUPPLY"), "status text out of supply")
	home.hp = max_hp * 0.5
	home.organization = max_org * 0.5
	notes.clear()
	tm.advance_days(1)
	check(absf(cut.hp - max_hp * 0.98) < 0.01, "out of supply: -2% max HP per day")
	check(absf(cut.organization - max_org * 0.95) < 0.01, "out of supply: -5% max org per day")
	check(home.hp > max_hp * 0.5 and home.organization > max_org * 0.5, "in-supply division recovers")
	var found := false
	for t in notes:
		if String(t).contains("out of supply in Moscow"):
			found = true
	check(found, "player notified of division out of supply")
	cut.organization = max_org * 0.5
	tm.advance_days(1)
	check(cut.organization < max_org * 0.5, "no org recovery out of supply")
	check(absf(cut.hp - max_hp * 0.96) < 0.01, "attrition continues (2 days)")

	# Save / load keeps supply state (derived from the map).
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(data)
	var cut2 = gs.division(cut.id)
	check(cut2 != null and not sp.is_supplied(cut2), "out of supply after save/load")

	# Reconnect: supply restored, attrition stops.
	notes.clear()
	changed.clear()
	gs.province("moscow").controller = "germany"
	for p in ["poland", "belarus"]:
		gs.province(p).controller = "germany"
		bus.province_changed.emit(p)
	await process_frame
	check(changed.has("germany"), "supply_changed(germany) after reconnecting")
	check(sp.is_supplied(cut2), "Moscow reconnected via Poland/Belarus")
	var hp_before: float = cut2.hp
	tm.advance_days(1)
	check(cut2.hp >= hp_before, "no attrition once supplied")
	found = false
	for t in notes:
		if String(t).contains("Supply restored"):
			found = true
	check(found, "player notified of supply restored")

	# Destruction at 0 HP.
	gs.new_game("germany")
	gs.province("moscow").controller = "germany"
	var doomed = gs.add_division("infantry", "germany", "moscow")
	var did: int = doomed.id
	doomed.hp = 0.5
	tm.advance_days(1)
	check(gs.division(did) == null, "division destroyed by attrition at 0 HP")

	# AI divisions suffer too; capitulated nations skipped.
	gs.new_game("germany")
	var ai2 = gs.add_division("infantry", "poland", "east_prussia")
	gs.province("east_prussia").controller = "ussr"
	var hp0: float = ai2.hp
	tm.advance_days(1)
	check(ai2.hp < hp0, "AI division in foreign-held province takes attrition")
	gs.nation("poland").capitulated = true
	var hp1: float = ai2.hp
	tm.advance_days(1)
	check_eq(ai2.hp, hp1, "capitulated nation skipped")
