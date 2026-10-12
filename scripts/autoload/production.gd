extends Node
## Production / economy system (autoload "Production", step 6).
##
## Runs once per in-game day through Simulation ("production", order 10), for
## every nation that has not capitulated, in this order:
##   1. resource income: steel + oil of every controlled province + colonial income
##   2. manpower growth: nations.json manpower_daily x tech manpower multiplier
##   3. factory construction: every queued factory in an owned + controlled
##      province counts down one day; at 0 the province gains a factory
##      (EventBus.factory_completed(pid) + province_changed(pid))
##   4. equipment production: factories assigned to an equipment type add
##      factories x rules.production_per_factory x tech production multiplier
##      points per day; every `cost` points becomes one unit if the stockpile has
##      the steel/oil it needs (equipment.json "resources"). Without resources
##      production stalls with at most one finished unit's worth of progress.
## Then EventBus.nation_changed(nid) is emitted for each processed nation.
##
## All state lives in GameState (NationState.factory_allocation,
## production_progress, stockpile; ProvinceState.factory_queue), so it saves.
## `shortages` (nation -> {equipment: true}) is derived and rebuilt daily.

const RESOURCE_KEYS: PackedStringArray = ["steel", "oil"]

## nid -> {equipment_id: true} for equipment that stalled on resources last day.
var shortages: Dictionary = {}
## Days processed (tests / debugging).
var days_processed: int = 0


func _ready() -> void:
	Simulation.register_daily("production", run_daily, 10)
	EventBus.game_state_ready.connect(_on_game_state_ready)
	EventBus.province_changed.connect(_on_province_changed)


func _on_game_state_ready() -> void:
	# Loaded state is kept exactly as saved (allocations are clamped daily in _produce).
	shortages.clear()


func _on_province_changed(pid: String) -> void:
	# Losing a province can leave more factories assigned than a nation has.
	if not GameState.active:
		return
	var ps: ProvinceState = GameState.province(pid)
	if ps == null:
		return
	for nid in GameState.nations:
		if allocated_total(nid) > available_factories(nid):
			sanitize_allocation(nid)
			EventBus.nation_changed.emit(nid)


# --- Daily tick ----------------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	days_processed += 1
	var changed: Array[String] = []
	for nid in GameData.nation_ids:
		var n: NationState = GameState.nation(nid)
		if n == null or n.capitulated:
			continue
		_collect_income(n)
		_grow_manpower(n)
		_build_factories(n)
		_produce(n)
		changed.append(nid)
	for nid in changed:
		EventBus.nation_changed.emit(nid)


func _collect_income(n: NationState) -> void:
	var income := resource_income(n.id)
	for k in RESOURCE_KEYS:
		n.stockpile[k] = float(n.stockpile.get(k, 0.0)) + float(income[k])


func _grow_manpower(n: NationState) -> void:
	n.manpower += manpower_growth(n.id)


func _build_factories(n: NationState) -> void:
	for pid in GameData.province_ids:
		var ps: ProvinceState = GameState.province(pid)
		if ps.factory_queue.is_empty() or ps.owner != n.id or ps.controller != n.id:
			continue   # construction pauses while the province is occupied
		var finished := 0
		for item: Dictionary in ps.factory_queue:
			item.days_left = int(item.days_left) - 1
			if int(item.days_left) <= 0:
				finished += 1
		if finished == 0:
			continue
		ps.factory_queue = ps.factory_queue.filter(func(it: Dictionary) -> bool: return int(it.days_left) > 0)
		ps.factories += finished
		for i in finished:
			EventBus.factory_completed.emit(pid)
		EventBus.province_changed.emit(pid)


func _produce(n: NationState) -> void:
	sanitize_allocation(n.id)
	var short: Dictionary = {}
	var per_factory := points_per_factory(n.id)
	for eq in GameData.equipment_ids:
		var assigned := int(n.factory_allocation.get(eq, 0))
		var cost := equipment_cost(eq)
		if assigned <= 0 or cost <= 0.0:
			continue
		var progress := float(n.production_progress.get(eq, 0.0)) + assigned * per_factory
		var units := int(floor(progress / cost + 0.000001))
		var affordable := affordable_units(n, eq)
		if units > affordable:
			units = affordable
			short[eq] = true
		if units > 0:
			var res: Dictionary = GameData.equipment[eq].get("resources", {})
			for k in RESOURCE_KEYS:
				n.stockpile[k] = maxf(0.0, float(n.stockpile.get(k, 0.0)) - units * float(res.get(k, 0.0)))
			n.stockpile[eq] = float(n.stockpile.get(eq, 0.0)) + units
			progress -= units * cost
		if short.has(eq):
			progress = minf(progress, cost)   # stalled: keep at most one unit's worth
		n.production_progress[eq] = maxf(0.0, progress)
	shortages[n.id] = short


# --- Queries -------------------------------------------------------------------

## Factories the nation can assign (all factories in provinces it controls).
func available_factories(nid: String) -> int:
	return GameState.factory_count(nid)


func allocated_total(nid: String) -> int:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return 0
	var total := 0
	for eq in GameData.equipment_ids:
		total += int(n.factory_allocation.get(eq, 0))
	return total


func free_factories(nid: String) -> int:
	return maxi(0, available_factories(nid) - allocated_total(nid))


func allocation(nid: String, eq: String) -> int:
	var n: NationState = GameState.nation(nid)
	return int(n.factory_allocation.get(eq, 0)) if n else 0


func equipment_cost(eq: String) -> float:
	return float(GameData.equipment.get(eq, {}).get("cost", 0.0))


## Production points one factory adds per day (rules x research multiplier).
func points_per_factory(nid: String) -> float:
	var n: NationState = GameState.nation(nid)
	var mult := TechEffects.production_multiplier(n.researched) if n else 1.0
	return float(GameData.rule("production_per_factory", 1.0)) * mult


## Expected units per day of [param eq] at the current allocation (ignores shortages).
func daily_output(nid: String, eq: String) -> float:
	var cost := equipment_cost(eq)
	if cost <= 0.0:
		return 0.0
	return allocation(nid, eq) * points_per_factory(nid) / cost


## Expected steel/oil used per day by the current allocation: {"steel", "oil"}.
func daily_resource_use(nid: String) -> Dictionary:
	var out := {"steel": 0.0, "oil": 0.0}
	for eq in GameData.equipment_ids:
		var units := daily_output(nid, eq)
		var res: Dictionary = GameData.equipment[eq].get("resources", {})
		for k in RESOURCE_KEYS:
			out[k] += units * float(res.get(k, 0.0))
	return out


## Steel/oil gained per day from controlled provinces + colonial income: {"steel", "oil"}.
func resource_income(nid: String) -> Dictionary:
	var out := {"steel": 0.0, "oil": 0.0}
	if not GameState.active:
		return out
	for pid in GameState.controlled_provinces(nid):
		var res: Dictionary = GameData.province(pid).get("resources", {})
		for k in RESOURCE_KEYS:
			out[k] += float(res.get(k, 0.0))
	var colonial: Dictionary = GameData.nation(nid).get("colonial_income", {})
	for k in RESOURCE_KEYS:
		out[k] += float(colonial.get(k, 0.0))
	return out


## Expected net change of steel/oil per day (income - production use).
func daily_net(nid: String) -> Dictionary:
	var inc := resource_income(nid)
	var use := daily_resource_use(nid)
	return {"steel": inc.steel - use.steel, "oil": inc.oil - use.oil}


func manpower_growth(nid: String) -> int:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return 0
	var base := float(GameData.nation(nid).get("manpower_daily", 0))
	return int(round(base * TechEffects.manpower_growth_multiplier(n.researched)))


## Units of [param eq] the stockpile's steel/oil can pay for right now.
func affordable_units(n: NationState, eq: String) -> int:
	var res: Dictionary = GameData.equipment.get(eq, {}).get("resources", {})
	var best := 1 << 30
	for k in RESOURCE_KEYS:
		var need := float(res.get(k, 0.0))
		if need > 0.0:
			best = mini(best, int(floor(float(n.stockpile.get(k, 0.0)) / need + 0.000001)))
	return best


func is_short(nid: String, eq: String) -> bool:
	return shortages.get(nid, {}).has(eq)


# --- Factory allocation ----------------------------------------------------------

## Assign [param count] factories to [param eq] (clamped to 0..assigned+free).
## Returns the new allocation. Emits nation_changed when it changes.
func set_allocation(nid: String, eq: String, count: int) -> int:
	var n: NationState = GameState.nation(nid)
	if n == null or not GameData.equipment.has(eq):
		return 0
	var current := int(n.factory_allocation.get(eq, 0))
	var target := clampi(count, 0, current + free_factories(nid))
	if target != current:
		n.factory_allocation[eq] = target
		EventBus.nation_changed.emit(nid)
	return target


func change_allocation(nid: String, eq: String, delta: int) -> int:
	return set_allocation(nid, eq, allocation(nid, eq) + delta)


## Clamp allocations so their total fits the available factories (removes
## from the last equipment type first). Returns true if anything changed.
func sanitize_allocation(nid: String) -> bool:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return false
	var changed := false
	for eq in GameData.equipment_ids:
		if not n.factory_allocation.has(eq) or int(n.factory_allocation[eq]) < 0:
			n.factory_allocation[eq] = 0
			changed = true
	var excess := allocated_total(nid) - available_factories(nid)
	var ids := GameData.equipment_ids.duplicate()
	ids.reverse()
	for eq in ids:
		if excess <= 0:
			break
		var take := mini(excess, int(n.factory_allocation[eq]))
		if take > 0:
			n.factory_allocation[eq] = int(n.factory_allocation[eq]) - take
			excess -= take
			changed = true
	return changed


## Split all of a nation's factories by rules.default_production_split
## (used for new games; remainder goes to the first equipment type).
func apply_default_allocation(nid: String) -> void:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return
	var split: Dictionary = GameData.rule("default_production_split", {})
	var total := available_factories(nid)
	var used := 0
	for eq in GameData.equipment_ids:
		var c := int(floor(total * float(split.get(eq, 0.0))))
		n.factory_allocation[eq] = c
		used += c
	if GameData.equipment_ids.size() > 0:
		var first: String = GameData.equipment_ids[0]
		n.factory_allocation[first] = int(n.factory_allocation[first]) + maxi(0, total - used)


# --- Factory construction ----------------------------------------------------------

func factory_build_days() -> int:
	return int(GameData.rule("factory_build_days", 120))


func factory_build_cost() -> float:
	return float(GameData.rule("factory_build_cost_steel", 50))


func max_factories_per_province() -> int:
	return int(GameData.rule("max_factories_per_province", 15))


## "" if [param nid] may start a factory in [param pid] now, else the reason.
func build_factory_error(nid: String, pid: String) -> String:
	if not GameState.active:
		return "No game running"
	var ps: ProvinceState = GameState.province(pid)
	var n: NationState = GameState.nation(nid)
	if ps == null or n == null:
		return "Unknown province"
	if GameData.is_naval(pid):
		return "Cannot build in a naval zone"
	if ps.owner != nid:
		return "You do not own this province"
	if ps.controller != nid:
		return "Province is occupied"
	if ps.factories + ps.factory_queue.size() >= max_factories_per_province():
		return "Province is full (max %d factories)" % max_factories_per_province()
	if float(n.stockpile.get("steel", 0.0)) + 0.000001 < factory_build_cost():
		return "Needs %d steel" % int(factory_build_cost())
	return ""


func can_build_factory(nid: String, pid: String) -> bool:
	return build_factory_error(nid, pid) == ""


## Pay the steel and queue a factory. Returns false (and changes nothing) if not allowed.
func build_factory(nid: String, pid: String) -> bool:
	if not can_build_factory(nid, pid):
		return false
	var n: NationState = GameState.nation(nid)
	n.stockpile["steel"] = float(n.stockpile.get("steel", 0.0)) - factory_build_cost()
	GameState.province(pid).factory_queue.append({"days_left": factory_build_days()})
	EventBus.province_changed.emit(pid)
	EventBus.nation_changed.emit(nid)
	return true


## Factories under construction for [param nid]: Array of {"province", "days_left"},
## soonest first.
func construction_list(nid: String) -> Array:
	var out: Array = []
	if not GameState.active:
		return out
	for pid in GameData.province_ids:
		var ps: ProvinceState = GameState.province(pid)
		if ps.owner != nid:
			continue
		for item: Dictionary in ps.factory_queue:
			out.append({"province": pid, "days_left": int(item.days_left), "paused": ps.controller != nid})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.days_left < b.days_left)
	return out


## Provinces where [param nid] could ever build (owned land provinces), doc order.
func buildable_provinces(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not GameState.active:
		return out
	for pid in GameState.owned_provinces(nid):
		if not GameData.is_naval(pid):
			out.append(pid)
	return out
