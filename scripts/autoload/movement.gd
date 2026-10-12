extends Node
## Division movement (autoload "Movement", step 9).
##
## order_move(div_id, target) finds a BFS path (fewest provinces) from the
## division's province to the target and stores it in DivisionState.path
## (next province first). Every in-game day (Simulation daily system
## "movement", order 40) each moving division adds 1 / hop_days to
## move_progress; at 1.0 it enters path[0]: province/origin update,
## entrenchment resets and EventBus.division_moved(id, from, to) fires.
##
## Passable provinces (path steps): land provinces the owner controls or
## whose controller grants it military access; naval zones only if the owner
## controls them ("naval zones block land movement unless you own them").
## The final target may also be an adjacent enemy province (controller at war
## with the owner) - step 10 resolves combat on entry via `hostile_entry`.
##
## hop_days(template, owner, target) = movement_base_days / speed
##     x terrain move_cost x (1 - infrastructure_move_bonus x (infra - 3)).

const EPS := 0.000001

## Step 10 hook: if set, called as hostile_entry.call(division, province) when a
## division is about to enter a province controlled by an enemy. Return true to
## let it enter now, false to hold it at full progress (battle in progress).
var hostile_entry: Callable = Callable()
var days_processed: int = 0


func _ready() -> void:
	Simulation.register_daily("movement", run_daily, 40)


# --- Rules -------------------------------------------------------------------

## True if [param nid]'s divisions may pass through / stop in [param pid].
func is_passable(nid: String, pid: String) -> bool:
	var ps: ProvinceState = GameState.province(pid)
	if ps == null:
		return false
	if ps.controller == nid:
		return true
	if GameData.is_naval(pid):
		return false
	var n: NationState = GameState.nation(nid)
	return n != null and n.military_access.has(ps.controller)


## True if [param pid] is controlled by a nation [param nid] is at war with.
func is_hostile(nid: String, pid: String) -> bool:
	var ps: ProvinceState = GameState.province(pid)
	var n: NationState = GameState.nation(nid)
	if ps == null or n == null or GameData.is_naval(pid):
		return false
	return ps.controller != nid and n.is_at_war_with(ps.controller)


## BFS path from [param from] to [param to] (excluding from). Empty if none.
func find_path(nid: String, from: String, to: String) -> Array[String]:
	var out: Array[String] = []
	if from == to or GameState.province(to) == null:
		return out
	var target_ok := is_passable(nid, to) or is_hostile(nid, to)
	if not target_ok:
		return out
	var prev: Dictionary = {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for nb in GameData.adjacent(cur):
			if prev.has(nb):
				continue
			if nb == to:
				prev[nb] = cur
				var p := to
				while p != from:
					out.push_front(p)
					p = prev[p]
				return out
			if is_passable(nid, nb):
				prev[nb] = cur
				queue.append(nb)
	return out


func division_speed(d: DivisionState) -> float:
	var n: NationState = GameState.nation(d.owner)
	var stats := TechEffects.division_stats(d.template, n.researched if n else [])
	return maxf(0.1, float(stats.get("speed", 1.0)))


## Days a division of [param d]'s type needs to enter [param pid].
func hop_days(d: DivisionState, pid: String) -> float:
	var cost := float(GameData.terrain_of(pid).get("move_cost", 1.0))
	var infra := 3
	var ps: ProvinceState = GameState.province(pid)
	if ps and not GameData.is_naval(pid):
		infra = clampi(ps.infrastructure, 1, 5)
	var infra_mult := 1.0 - float(GameData.rule("infrastructure_move_bonus", 0.1)) * (infra - 3)
	return float(GameData.rule("movement_base_days", 16.0)) / division_speed(d) * cost * infra_mult


## Days until the division reaches the end of its path (0 when holding).
func eta_days(d: DivisionState) -> float:
	if d == null or not d.is_moving():
		return 0.0
	var total := hop_days(d, d.path[0]) * (1.0 - d.move_progress)
	for i in range(1, d.path.size()):
		total += hop_days(d, d.path[i])
	return total


## "" when the order is possible, else the reason.
func move_error(div_id: int, target: String) -> String:
	var d: DivisionState = GameState.division(div_id)
	if d == null:
		return "No such division"
	if GameState.province(target) == null:
		return "Unknown province"
	if d.province == target:
		return "Already there"
	var n: NationState = GameState.nation(d.owner)
	if n == null or n.capitulated:
		return "Nation has capitulated"
	if GameData.is_naval(target) and GameState.province(target).controller != d.owner:
		return "Naval zones block land movement unless you own them"
	if not is_passable(d.owner, target) and not is_hostile(d.owner, target):
		return "%s is not friendly territory" % GameData.province_name(target)
	if find_path(d.owner, d.province, target).is_empty():
		return "No route through friendly territory to %s" % GameData.province_name(target)
	return ""


func can_move(div_id: int, target: String) -> bool:
	return move_error(div_id, target) == ""


## Give a move order. Returns false (and changes nothing) if impossible.
func order_move(div_id: int, target: String) -> bool:
	if move_error(div_id, target) != "":
		return false
	var d: DivisionState = GameState.division(div_id)
	var path := find_path(d.owner, d.province, target)
	# Keep progress if still heading to the same next province.
	if not (d.is_moving() and d.path[0] == path[0]):
		d.move_progress = 0.0
	d.path = path
	d.entrenchment = 0.0
	EventBus.division_order_changed.emit(div_id)
	return true


## Order several divisions; returns how many accepted the order.
func order_move_group(ids: Array, target: String) -> int:
	var n := 0
	for did in ids:
		if order_move(int(did), target):
			n += 1
	return n


func stop(div_id: int) -> void:
	var d: DivisionState = GameState.division(div_id)
	if d == null or not d.is_moving():
		return
	d.path = []
	d.move_progress = 0.0
	EventBus.division_order_changed.emit(div_id)


# --- Daily tick -----------------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	days_processed += 1
	var ids: Array = GameState.divisions.keys()
	ids.sort()
	for did in ids:
		var d: DivisionState = GameState.division(did)
		if d == null or not d.is_moving():
			continue
		var n: NationState = GameState.nation(d.owner)
		if n == null or n.capitulated:
			continue
		_advance(d)


func _advance(d: DivisionState) -> void:
	var next: String = d.path[0]
	var hostile := is_hostile(d.owner, next)
	if not hostile and not is_passable(d.owner, next):
		_reroute(d)
		if not d.is_moving():
			return
		next = d.path[0]
		hostile = is_hostile(d.owner, next)
	d.move_progress = minf(1.0, d.move_progress + 1.0 / hop_days(d, next))
	if d.move_progress < 1.0 - EPS:
		return
	if hostile and hostile_entry.is_valid() and not bool(hostile_entry.call(d, next)):
		return
	enter_province(d, next)


## Move [param d] into path[0] (== [param next]) now: origin/province update,
## progress and entrenchment reset, division_moved (+ division_order_changed
## when the path is finished). Also used by Combat when attackers win.
func enter_province(d: DivisionState, next: String) -> void:
	var from := d.province
	if not d.path.is_empty() and d.path[0] == next:
		d.path.pop_front()
	else:
		d.path.clear()
	d.province = next
	d.origin = from
	d.move_progress = 0.0
	d.entrenchment = 0.0
	EventBus.division_moved.emit(d.id, from, next)
	if not d.is_moving():
		EventBus.division_order_changed.emit(d.id)


func _reroute(d: DivisionState) -> void:
	var target: String = d.path[-1]
	var path := find_path(d.owner, d.province, target)
	d.move_progress = 0.0
	d.path = path
	if path.is_empty() and d.owner == GameState.player_nation:
		EventBus.notify.emit("Division #%d halted: no route to %s" % [d.id, GameData.province_name(target)])
	EventBus.division_order_changed.emit(d.id)
