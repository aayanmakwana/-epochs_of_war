extends Node
## AI opponent (autoload "AI", step 14).
##
## Controls every nation the player is not playing. Simple if/else logic, run
## once per in-game day (Simulation daily system "ai", order 90, after all
## world systems so it reacts to the state of that day). Stateless: nothing is
## saved, every decision is derived from GameState.
##
## Per AI nation (not capitulated), in this order:
##   1. production: factories split by priority infantry equipment > armor >
##      artillery (all to infantry equipment while its stockpile is below
##      rules.ai_infantry_equipment_reserve; else half infantry equipment, half
##      of the rest armor - if unlocked and oil is available - and the rest
##      artillery).
##   2. research: when idle, the first available tech in branch order
##      (infantry, then armor, then doctrine).
##   3. recruitment: one infantry division per day in the default deploy
##      province while manpower and equipment allow (at most
##      rules.ai_max_recruit_queue in training).
##   4. positioning: half of the divisions (rounded up) are sent to border
##      provinces adjacent to enemies, spread over the least covered ones.
##      Enemies = nations at war with it, war goal targets, and scripted war
##      opponents within rules.ai_prepare_days of the declaration date.
##   5. attack: for every enemy province adjacent to its territory, if the idle
##      divisions next to it (with organization >= rules.ai_min_attack_org of
##      max, keeping one division in the capital) plus those already attacking
##      it are at least 2x the enemy garrison, they attack.
##   6. tactical battles: AI nations always auto-resolve (auto_resolves_tactical);
##      steps 15-17 ask this before prompting.
## No diplomacy AI: wars come from Diplomacy's scripted wars or the player.

const DAILY_ORDER := 90

## Turn the AI off (tests of other systems, debugging). Default rules.ai_enabled.
var enabled: bool = true
## Days processed (all nations) - for tests.
var days_run: int = 0
## Log of the last orders given: [{nation, kind, division, target}] (cleared daily).
var last_orders: Array = []


func _ready() -> void:
	enabled = bool(GameData.rule("ai_enabled", true))
	Simulation.register_daily("ai", run_daily, DAILY_ORDER)


func _r(key: String, def: float) -> float:
	return float(GameData.rule(key, def))


# --- Queries -----------------------------------------------------------------

## True if [param nid] is controlled by the AI (any nation but the player's).
func is_ai(nid: String) -> bool:
	return GameState.active and nid != GameState.player_nation and GameState.nation(nid) != null


## AI nations never enter tactical mode (design doc "AI Opponent" 5).
## True when a battle fought only by AI nations / for this nation auto-resolves.
func auto_resolves_tactical(nid: String) -> bool:
	return nid != GameState.player_nation


func ai_nations() -> PackedStringArray:
	var out: PackedStringArray = []
	for nid in GameData.nation_ids:
		var n: NationState = GameState.nation(nid)
		if n != null and not n.capitulated and is_ai(nid):
			out.append(nid)
	return out


## Nations [param nid] treats as enemies for positioning (see header).
func threat_nations(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var n: NationState = GameState.nation(nid)
	if n == null:
		return out
	for e in n.at_war_with:
		_add_threat(out, String(e))
	for t in n.war_goals.keys():
		_add_threat(out, String(t))
	var prepare := int(_r("ai_prepare_days", 60))
	for w: Dictionary in GameData.rule("scripted_wars", []):
		var dt: Array = w.get("date", [])
		if dt.size() < 3:
			continue
		var a := String(w.get("attacker", ""))
		var b := String(w.get("defender", ""))
		if a == GameState.player_nation or (nid != a and nid != b):
			continue
		var left := GameDate.to_index(int(dt[0]), int(dt[1]), int(dt[2])) - GameState.day_index
		if left < 0 or left > prepare:
			continue
		_add_threat(out, b if nid == a else a)
	return out


func _add_threat(out: PackedStringArray, other: String) -> void:
	var o: NationState = GameState.nation(other)
	if o != null and not o.capitulated and not out.has(other):
		out.append(other)


## Land provinces controlled by [param nid] adjacent to a land province
## controlled by one of [param enemies]. Province-id order.
func border_provinces(nid: String, enemies: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	if enemies.is_empty():
		return out
	for pid in GameData.province_ids:
		var ps: ProvinceState = GameState.province(pid)
		if ps == null or ps.controller != nid or GameData.is_naval(pid):
			continue
		for nb in GameData.adjacent(pid):
			var q: ProvinceState = GameState.province(nb)
			if q != null and not GameData.is_naval(nb) and enemies.has(q.controller):
				out.append(pid)
				break
	return out


## Province a division is in or heading to.
func destination(d: DivisionState) -> String:
	return d.path[-1] if d.is_moving() else d.province


func _is_idle(d: DivisionState) -> bool:
	return not d.is_moving() and not Combat.is_in_battle(d)


func _ready_to_attack(d: DivisionState) -> bool:
	var n: NationState = GameState.nation(d.owner)
	var stats := TechEffects.division_stats(d.template, n.researched if n else [])
	return d.organization + 0.0001 >= _r("ai_min_attack_org", 0.5) * float(stats.organization)


func _capital(nid: String) -> String:
	return String(GameData.nation(nid).get("capital", ""))


# --- Daily tick -----------------------------------------------------------------

func run_daily() -> void:
	last_orders.clear()
	if not enabled or not GameState.active or GameState.game_over:
		return
	days_run += 1
	for nid in ai_nations():
		run_nation(nid)


## One full AI turn for [param nid].
func run_nation(nid: String) -> void:
	manage_production(nid)
	manage_research(nid)
	manage_recruitment(nid)
	position_divisions(nid)
	launch_attacks(nid)


# --- 1. Production ---------------------------------------------------------------

## Wanted factory split {eq: count} for [param nid].
func desired_allocation(nid: String) -> Dictionary:
	var n: NationState = GameState.nation(nid)
	var total: int = Production.available_factories(nid)
	var out := {}
	for eq in GameData.equipment_ids:
		out[eq] = 0
	if n == null or total <= 0:
		return out
	if float(n.stockpile.get("infantry_equipment", 0.0)) < _r("ai_infantry_equipment_reserve", 200.0):
		out["infantry_equipment"] = total
		return out
	var inf := int(ceil(total / 2.0))
	var rest := total - inf
	var armor := 0
	if armor_allowed(nid):
		armor = int(ceil(rest / 2.0))
	out["infantry_equipment"] = inf
	out["armor"] = armor
	out["artillery"] = rest - armor
	return out


## Armor is produced only once unlocked and with oil income or stock.
func armor_allowed(nid: String) -> bool:
	var n: NationState = GameState.nation(nid)
	if n == null or not TechEffects.is_division_unlocked("armor", n.researched):
		return false
	var oil_per_unit := float(GameData.equipment.get("armor", {}).get("resources", {}).get("oil", 0.0))
	return float(Production.resource_income(nid).get("oil", 0.0)) > 0.0 \
		or float(n.stockpile.get("oil", 0.0)) >= oil_per_unit * 5.0


func manage_production(nid: String) -> void:
	var want := desired_allocation(nid)
	# Decreases first so the increases find free factories.
	for eq in GameData.equipment_ids:
		if int(want[eq]) < Production.allocation(nid, eq):
			Production.set_allocation(nid, eq, int(want[eq]))
	for eq in GameData.equipment_ids:
		if int(want[eq]) > Production.allocation(nid, eq):
			Production.set_allocation(nid, eq, int(want[eq]))


# --- 2. Research -------------------------------------------------------------------

## Next tech for [param nid]: first available in branch order (infantry, armor, doctrine).
func next_research(nid: String) -> String:
	var avail: PackedStringArray = Research.available_techs(nid)
	return avail[0] if not avail.is_empty() else ""


func manage_research(nid: String) -> void:
	if Research.current(nid) != "":
		return
	var tid := next_research(nid)
	if tid != "":
		Research.start_research(nid, tid)


# --- 3. Recruitment ----------------------------------------------------------------

func manage_recruitment(nid: String) -> void:
	if Recruitment.queued_count(nid) >= int(_r("ai_max_recruit_queue", 2)):
		return
	var pid: String = Recruitment.default_deploy_province(nid)
	if Recruitment.can_recruit(nid, "infantry", pid):
		Recruitment.recruit(nid, "infantry", pid)
		last_orders.append({"nation": nid, "kind": "recruit", "division": -1, "target": pid})


# --- 4. Positioning ------------------------------------------------------------------

func position_divisions(nid: String) -> void:
	var enemies := threat_nations(nid)
	var border := border_provinces(nid, enemies)
	if border.is_empty():
		return
	var divs: Array[DivisionState] = GameState.divisions_of(nid)
	var want := int(ceil(divs.size() / 2.0))
	var cover := {}
	for pid in border:
		cover[pid] = 0
	var at_border := 0
	var candidates: Array[DivisionState] = []
	for d in divs:
		var dest := destination(d)
		if cover.has(dest) or Combat.is_in_battle(d) or (d.is_moving() and Movement.is_hostile(nid, dest)):
			# Already on/heading to the border, or fighting (attacks start from the border).
			if cover.has(dest):
				cover[dest] = int(cover[dest]) + 1
			at_border += 1
		elif not d.is_moving():
			candidates.append(d)
	# Keep one division in the capital when it is not itself a border province.
	var cap := _capital(nid)
	var cap_count := 0
	for d in candidates:
		if d.province == cap:
			cap_count += 1
	for d in candidates:
		if at_border >= want:
			return
		if d.province == cap and cap_count <= 1 and divs.size() > 1:
			continue
		var target := _least_covered_reachable(d, border, cover)
		if target == "":
			continue
		if Movement.order_move(d.id, target):
			if d.province == cap:
				cap_count -= 1
			cover[target] = int(cover[target]) + 1
			at_border += 1
			last_orders.append({"nation": nid, "kind": "position", "division": d.id, "target": target})


func _least_covered_reachable(d: DivisionState, border: PackedStringArray, cover: Dictionary) -> String:
	var best := ""
	var best_cover := 1 << 30
	var best_len := 1 << 30
	for pid in border:
		var path := Movement.find_path(d.owner, d.province, pid)
		if path.is_empty():
			continue
		var c := int(cover[pid])
		if c < best_cover or (c == best_cover and path.size() < best_len):
			best = pid
			best_cover = c
			best_len = path.size()
	return best


# --- 5. Attacks ----------------------------------------------------------------------

## Enemy (at war) divisions in [param pid] that would defend against [param nid].
func garrison(nid: String, pid: String) -> int:
	return Combat.defenders(pid, nid).size()


## Enemy land provinces adjacent to [param nid]'s territory (at war only).
func attack_targets(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if not Movement.is_hostile(nid, pid):
			continue
		for nb in GameData.adjacent(pid):
			var q: ProvinceState = GameState.province(nb)
			if q != null and q.controller == nid:
				out.append(pid)
				break
	return out


func launch_attacks(nid: String) -> void:
	var cap := _capital(nid)
	for target in attack_targets(nid):
		var defenders := garrison(nid, target)
		var already := 0
		for d in GameState.divisions_of(nid):
			if d.is_moving() and d.path[0] == target:
				already += 1
		var ready: Array[DivisionState] = []
		for nb in GameData.adjacent(target):
			var q: ProvinceState = GameState.province(nb)
			if q == null or q.controller != nid:
				continue
			var here: Array[DivisionState] = []
			for d in GameState.divisions_in(nb):
				if d.owner == nid and _is_idle(d) and _ready_to_attack(d):
					here.append(d)
			if nb == cap and not here.is_empty() and _count_idle_in(nid, cap) <= here.size():
				here.pop_back()   # never strip the capital
			ready.append_array(here)
		if ready.is_empty():
			continue
		if ready.size() + already < 2 * defenders:
			continue
		for d in ready:
			if Movement.order_move(d.id, target):
				last_orders.append({"nation": nid, "kind": "attack", "division": d.id, "target": target})


func _count_idle_in(nid: String, pid: String) -> int:
	var c := 0
	for d in GameState.divisions_in(pid):
		if d.owner == nid and _is_idle(d):
			c += 1
	return c
