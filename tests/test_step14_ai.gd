extends "res://tests/test_base.gd"
## Step 14: AI opponent. Covers the six behaviours of the design doc
## ("AI Opponent"): build infantry when manpower + equipment allow, research
## infantry > armor > doctrine, half the divisions on borders adjacent to
## enemies, attack at 2x the adjacent enemy garrison, never tactical mode,
## production priority infantry equipment > armor > artillery. Plus: player
## nation untouched, enabled toggle, pre-war preparation for scripted wars.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var gs: Node
var gd: Node
var ai: Node
var dp: Node
var tm: Node
var rec: Node
var res: Node
var prod: Node
var mv: Node
var cb: Node


func run_tests() -> void:
	gs = autoload("GameState")
	gd = autoload("GameData")
	ai = autoload("AI")
	dp = autoload("Diplomacy")
	tm = autoload("TimeManager")
	rec = autoload("Recruitment")
	res = autoload("Research")
	prod = autoload("Production")
	mv = autoload("Movement")
	cb = autoload("Combat")
	var sim: Node = autoload("Simulation")
	check(ai != null, "AI autoload present")
	if ai == null:
		return
	check(sim.daily_systems().has("ai"), "ai daily system registered")
	check(ai.enabled, "AI enabled by default")
	check(bool(gd.rule("ai_enabled", false)), "rules.ai_enabled")

	_test_who_is_ai()
	_test_production()
	_test_research()
	_test_recruitment()
	_test_prewar_threats()
	_test_positioning()
	_test_attack()
	_test_player_untouched()
	_test_toggle()
	ai.enabled = true


# --- AI nations / tactical mode (behaviour 5) ----------------------------------

func _test_who_is_ai() -> void:
	gs.new_game("uk")
	check(ai.is_ai("germany") and ai.is_ai("ussr") and ai.is_ai("poland"), "non-player nations are AI")
	check(not ai.is_ai("uk"), "player nation is not AI")
	check(not ai.ai_nations().has("uk"), "ai_nations excludes player")
	check_eq(ai.ai_nations().size(), gd.nation_ids.size() - 1, "all other nations are AI")
	check(ai.auto_resolves_tactical("germany"), "AI Germany auto-resolves tactical battles")
	check(ai.auto_resolves_tactical("poland"), "AI Poland auto-resolves tactical battles")
	check(not ai.auto_resolves_tactical("uk"), "player may enter tactical mode")
	gs.nation("poland").capitulated = true
	check(not ai.ai_nations().has("poland"), "capitulated nations skipped")


# --- Production priority (behaviour 6) ------------------------------------------

func _test_production() -> void:
	gs.new_game("uk")
	var de = gs.nation("germany")
	var total: int = prod.available_factories("germany")
	check(total > 4, "Germany has factories")
	# Low infantry equipment: everything to infantry equipment.
	de.stockpile.infantry_equipment = 0.0
	ai.manage_production("germany")
	check_eq(prod.allocation("germany", "infantry_equipment"), total, "all factories to infantry equipment while short")
	check_eq(prod.allocation("germany", "armor"), 0, "no armor while short of infantry equipment")
	check_eq(prod.allocation("germany", "artillery"), 0, "no artillery while short of infantry equipment")
	# Enough stock: half infantry, then armor, then artillery.
	de.stockpile.infantry_equipment = 1000.0
	ai.manage_production("germany")
	var inf: int = prod.allocation("germany", "infantry_equipment")
	var arm: int = prod.allocation("germany", "armor")
	var art: int = prod.allocation("germany", "artillery")
	check_eq(inf + arm + art, total, "every factory assigned")
	check_eq(inf, int(ceil(total / 2.0)), "half (rounded up) to infantry equipment")
	check(inf >= arm and arm >= art and arm > 0, "priority infantry equipment > armor > artillery (%d/%d/%d)" % [inf, arm, art])
	check_eq(prod.free_factories("germany"), 0, "no idle factories")
	# Armor locked (Poland: no light tanks): armor share goes to artillery.
	var po = gs.nation("poland")
	po.stockpile.infantry_equipment = 1000.0
	var pt: int = prod.available_factories("poland")
	ai.manage_production("poland")
	check_eq(prod.allocation("poland", "armor"), 0, "no armor without light tanks")
	check_eq(prod.allocation("poland", "infantry_equipment"), int(ceil(pt / 2.0)), "Poland half to infantry equipment")
	check_eq(prod.allocation("poland", "artillery"), pt - int(ceil(pt / 2.0)), "Poland rest to artillery")
	# Via the daily tick, AI Germany re-balances (stock low again).
	de.stockpile.infantry_equipment = 0.0
	tm.advance_days(1)
	check_eq(prod.allocation("germany", "infantry_equipment"), total, "daily tick applies AI production")


# --- Research order (behaviour 2) ------------------------------------------------

func _test_research() -> void:
	gs.new_game("uk")
	var de = gs.nation("germany")
	check_eq(ai.next_research("germany"), "improved_infantry", "infantry branch first")
	tm.advance_days(1)
	check_eq(res.current("germany"), "improved_infantry", "AI Germany researching infantry after a day")
	check_eq(res.current("ussr"), "improved_infantry", "AI USSR researching infantry")
	check_eq(res.current("poland"), "basic_infantry", "AI Poland starts at basic infantry")
	check_eq(res.current("uk"), "", "player research untouched")
	# Switching is not done while something is in progress.
	ai.manage_research("germany")
	check_eq(res.current("germany"), "improved_infantry", "keeps current research")
	# Infantry branch complete -> armor; armor complete -> doctrine.
	res.cancel_research("germany")
	for tid in gd.techs_in_branch("infantry"):
		if not de.researched.has(tid):
			de.researched.append(tid)
	check_eq(ai.next_research("germany"), "medium_tanks", "armor after infantry")
	ai.manage_research("germany")
	check_eq(res.current("germany"), "medium_tanks", "AI starts armor research")
	res.cancel_research("germany")
	for tid in gd.techs_in_branch("armor"):
		if not de.researched.has(tid):
			de.researched.append(tid)
	check_eq(ai.next_research("germany"), "mass_assault", "doctrine after armor")
	for tid in gd.techs_in_branch("doctrine"):
		if not de.researched.has(tid):
			de.researched.append(tid)
	check_eq(ai.next_research("germany"), "", "nothing left to research")
	ai.manage_research("germany")
	check_eq(res.current("germany"), "", "idle when tree complete")


# --- Build infantry (behaviour 1) -------------------------------------------------

func _test_recruitment() -> void:
	gs.new_game("uk")
	var de = gs.nation("germany")
	de.stockpile.infantry_equipment = 1000.0
	var mp0: int = de.manpower
	ai.manage_recruitment("germany")
	check_eq(de.recruit_queue.size(), 1, "AI recruits with manpower and equipment")
	check_eq(String(de.recruit_queue[0].template), "infantry", "AI builds infantry")
	check_eq(String(de.recruit_queue[0].province), "berlin", "deployed in the capital")
	check_eq(de.manpower, mp0 - rec.manpower_cost("infantry"), "AI pays manpower")
	ai.manage_recruitment("germany")
	check_eq(de.recruit_queue.size(), 2, "second division queued")
	ai.manage_recruitment("germany")
	check_eq(de.recruit_queue.size(), int(gd.rule("ai_max_recruit_queue", 2)), "queue capped at ai_max_recruit_queue")
	# No manpower -> nothing.
	gs.new_game("uk")
	de = gs.nation("germany")
	de.stockpile.infantry_equipment = 1000.0
	de.manpower = 100
	ai.manage_recruitment("germany")
	check(de.recruit_queue.is_empty(), "no recruitment without manpower")
	# No equipment -> nothing.
	de.manpower = 900000
	de.stockpile.infantry_equipment = 10.0
	ai.manage_recruitment("germany")
	check(de.recruit_queue.is_empty(), "no recruitment without equipment")
	# Through the daily tick, divisions appear after training.
	gs.new_game("uk")
	de = gs.nation("germany")
	de.stockpile.infantry_equipment = 1000.0
	var n0: int = gs.divisions_of("germany").size()
	tm.advance_days(1)
	check(de.recruit_queue.size() >= 1, "daily tick recruits")
	tm.advance_days(int(rec.recruit_days("infantry")))
	check(gs.divisions_of("germany").size() > n0, "AI division created after training")
	check(gs.nation("uk").recruit_queue.is_empty(), "player recruitment untouched")


# --- Pre-war threats -----------------------------------------------------------------

func _test_prewar_threats() -> void:
	gs.new_game("uk")
	check(ai.threat_nations("germany").is_empty(), "no threats in 1936")
	var war_day: int = GameDate.to_index(1939, 9, 1)
	gs.day_index = war_day - int(gd.rule("ai_prepare_days", 60)) - 1
	check(not ai.threat_nations("germany").has("poland"), "Poland not a threat before the prepare window")
	gs.day_index = war_day - 30
	check(ai.threat_nations("germany").has("poland"), "Germany prepares 30 days before the Polish war")
	check(ai.threat_nations("poland").has("germany"), "Poland prepares too")
	check(not ai.threat_nations("germany").has("france"), "France war still far away")
	gs.new_game("germany")
	gs.day_index = war_day - 30
	check(ai.threat_nations("poland").is_empty(), "no scripted threat when the attacker is the player")
	gs.new_game("uk")
	dp.start_justification("ussr", "romania")
	check(ai.threat_nations("ussr").has("romania"), "war goal target is a threat")


# --- Positioning (behaviour 3) -------------------------------------------------------

func _border_set(nid: String, enemy: String) -> Dictionary:
	var out := {}
	for pid in gd.province_ids:
		if gs.province(pid).controller != nid or gd.is_naval(pid):
			continue
		for nb in gd.adjacent(pid):
			if not gd.is_naval(nb) and gs.province(nb).controller == enemy:
				out[pid] = true
	return out


func _test_positioning() -> void:
	gs.new_game("uk")
	check(ai.border_provinces("germany", PackedStringArray()).is_empty(), "no border without enemies")
	dp._start_war("germany", "poland")
	var expected := _border_set("germany", "poland")
	var border: PackedStringArray = ai.border_provinces("germany", ai.threat_nations("germany"))
	check(not border.is_empty(), "Germany has a border with Poland")
	var same := border.size() == expected.size()
	for pid in border:
		same = same and expected.has(pid)
	check(same, "border provinces = German provinces adjacent to Poland (%s)" % ", ".join(border))
	# Spread divisions away from the border so the AI must move them.
	var divs: Array = gs.divisions_of("germany")
	var interior := ""
	for pid in gs.controlled_provinces("germany"):
		if not expected.has(pid) and not gd.is_naval(pid) and pid != "berlin":
			interior = pid
	check(interior != "", "Germany has an interior province (%s)" % interior)
	for d in divs:
		d.province = interior
		d.origin = interior
	ai.position_divisions("germany")
	var at_border := 0
	for d in divs:
		if expected.has(ai.destination(d)):
			at_border += 1
	var want := int(ceil(divs.size() / 2.0))
	check_eq(at_border, want, "half the divisions (rounded up) sent to the border")
	var targets := {}
	for o in ai.last_orders:
		if o.kind == "position":
			check(expected.has(o.target), "position order targets a border province (%s)" % o.target)
			targets[o.target] = true
	if expected.size() > 1:
		check(targets.size() > 1, "divisions spread over several border provinces")
	# Running again does not send more.
	ai.last_orders.clear()
	ai.position_divisions("germany")
	check(ai.last_orders.is_empty(), "no extra orders once half are on the border")
	# Divisions actually walk there on the daily tick (AI attack may follow later).
	ai.enabled = false
	tm.advance_days(12)
	var arrived := 0
	for d in gs.divisions_of("germany"):
		if expected.has(d.province):
			arrived += 1
	check(arrived >= 1, "divisions arrive on the border")
	ai.enabled = true
	# Capital keeps one division when it is not a border province.
	gs.new_game("uk")
	dp._start_war("germany", "poland")
	expected = _border_set("germany", "poland")
	if not expected.has("berlin"):
		divs = gs.divisions_of("germany")
		for d in divs:
			d.province = "berlin"
			d.origin = "berlin"
		ai.position_divisions("germany")
		var home := 0
		for d in divs:
			if not d.is_moving():
				home += 1
		check(home >= 1, "capital never stripped")


# --- Attack (behaviour 4) ------------------------------------------------------------

func _clear_divisions(nid: String) -> void:
	for d in gs.divisions_of(nid):
		gs.remove_division(d.id)


func _test_attack() -> void:
	gs.new_game("uk")
	dp._start_war("germany", "poland")
	var expected := _border_set("germany", "poland")
	var b := ""
	for pid in expected:
		if pid != "berlin":
			b = pid
	if b == "":
		b = expected.keys()[0]
	_clear_divisions("germany")
	var garrison: int = ai.garrison("germany", "poland")
	check_eq(garrison, 2, "Poland garrison = 2 divisions")
	check(ai.attack_targets("germany").has("poland"), "Poland is an attack target")
	var keep := 1 if b == "berlin" else 0
	var ids: Array = []
	for i in 2 * garrison - 1 + keep:
		ids.append(gs.add_division("infantry", "germany", b).id)
	ai.launch_attacks("germany")
	var moving := 0
	for did in ids:
		if gs.division(did).is_moving():
			moving += 1
	check_eq(moving, 0, "no attack below 2x the garrison (%d vs %d)" % [ids.size() - keep, garrison])
	ids.append(gs.add_division("infantry", "germany", b).id)
	ai.launch_attacks("germany")
	moving = 0
	for did in ids:
		var d = gs.division(did)
		if d.is_moving() and d.path[0] == "poland":
			moving += 1
	check_eq(moving, 2 * garrison, "attack with 2x the garrison")
	# Low organization: no attack.
	gs.new_game("uk")
	dp._start_war("germany", "poland")
	_clear_divisions("germany")
	ids.clear()
	for i in 2 * garrison + 1 + keep:
		var d = gs.add_division("infantry", "germany", b)
		d.organization = 1.0
		ids.append(d.id)
	ai.launch_attacks("germany")
	moving = 0
	for did in ids:
		if gs.division(did).is_moving():
			moving += 1
	check_eq(moving, 0, "no attack with exhausted divisions")
	# Undefended enemy province: a single division attacks.
	gs.new_game("uk")
	dp._start_war("germany", "poland")
	_clear_divisions("germany")
	_clear_divisions("poland")
	var lone = gs.add_division("infantry", "germany", b)
	if keep == 1:
		gs.add_division("infantry", "germany", b)
	ai.launch_attacks("germany")
	check(lone.is_moving() and lone.path[0] == "poland" or gs.divisions_in(b).any(func(x) -> bool: return x.is_moving()),
		"undefended province attacked")
	# Full loop through the daily tick: Germany with a big army takes Poland.
	gs.new_game("uk")
	dp._start_war("germany", "poland")
	_clear_divisions("germany")
	for i in 6:
		gs.add_division("infantry", "germany", b)
	gs.add_division("infantry", "germany", "berlin")
	# A strong attack may win within the battle's first tick, so watch the signal.
	var started: Array = []
	var on_battle := func(pid: String) -> void: started.append(pid)
	var bus: Node = autoload("EventBus")
	bus.battle_started.connect(on_battle)
	for day in 60:
		tm.advance_days(1)
		if gs.province("poland").controller == "germany":
			break
	bus.battle_started.disconnect(on_battle)
	check(started.has("poland"), "AI attack starts a battle for Poland")
	check_eq(gs.province("poland").controller, "germany", "AI Germany captures Poland")


# --- Player untouched / toggle --------------------------------------------------------

func _test_player_untouched() -> void:
	gs.new_game("germany")
	var de = gs.nation("germany")
	var alloc0: Dictionary = de.factory_allocation.duplicate()
	var pos := {}
	for d in gs.divisions_of("germany"):
		pos[d.id] = d.province
	tm.advance_days(40)
	check_eq(de.factory_allocation, alloc0, "player production untouched")
	check_eq(res.current("germany"), "", "player research untouched")
	check(de.recruit_queue.is_empty(), "player recruitment untouched")
	var same := true
	for d in gs.divisions_of("germany"):
		same = same and pos.get(d.id, "") == d.province and not d.is_moving()
	check(same, "player divisions not moved")
	check(res.current("ussr") != "" or gs.nation("ussr").researched.size() > 2, "AI USSR researched meanwhile")


func _test_toggle() -> void:
	gs.new_game("uk")
	ai.enabled = false
	var d0: int = ai.days_run
	tm.advance_days(3)
	check_eq(ai.days_run, d0, "disabled AI does not run")
	check_eq(res.current("germany"), "", "disabled AI does not research")
	check(gs.nation("germany").recruit_queue.is_empty(), "disabled AI does not recruit")
	ai.enabled = true
	tm.advance_days(1)
	check_eq(ai.days_run, d0 + 1, "re-enabled AI runs")
