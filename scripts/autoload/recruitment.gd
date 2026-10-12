extends Node
## Military recruitment (autoload "Recruitment", step 8).
##
## Recruiting a division pays its full cost up front (template "manpower" from
## NationState.manpower and template "equipment" from NationState.stockpile) and
## appends {template, province, days_left} to NationState.recruit_queue. Every
## in-game day (Simulation "recruitment", order 30, after production/research)
## all queued divisions of every non-capitulated nation train in parallel;
## when days_left reaches 0 the division is created with GameState.add_division
## in its deployment province and EventBus.division_created(id) is emitted
## (+ notify(text) for the player).
##
## Deployment provinces: land provinces the nation both owns and controls.
## If the chosen province was lost while training, the division deploys in the
## capital (or the first valid province); with none left it waits.
## Cancelling a queued division refunds its full cost.
## Manpower growth is in Production (step 6); this system only spends it.

## Days processed (tests / debugging).
var days_processed: int = 0


func _ready() -> void:
	Simulation.register_daily("recruitment", run_daily, 30)


# --- Daily tick ----------------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	days_processed += 1
	for nid in GameData.nation_ids:
		var n: NationState = GameState.nation(nid)
		if n == null or n.capitulated or n.recruit_queue.is_empty():
			continue
		var remaining: Array = []
		var created: Array[int] = []
		for item: Dictionary in n.recruit_queue:
			item.days_left = maxi(0, int(item.days_left) - 1)
			if int(item.days_left) > 0:
				remaining.append(item)
				continue
			var pid := _deploy_target(nid, String(item.province))
			if pid == "":
				remaining.append(item)   # nowhere to deploy: wait at 0 days
				continue
			var d: DivisionState = GameState.add_division(String(item.template), nid, pid)
			created.append(d.id)
		n.recruit_queue = remaining
		for did in created:
			var d: DivisionState = GameState.division(did)
			EventBus.division_created.emit(did)
			if nid == GameState.player_nation:
				EventBus.notify.emit("%s ready in %s" % [template_name(d.template), GameData.province_name(d.province)])
		EventBus.nation_changed.emit(nid)


func _deploy_target(nid: String, wanted: String) -> String:
	if is_valid_deploy(nid, wanted):
		return wanted
	return default_deploy_province(nid)


# --- Queries -------------------------------------------------------------------

func template_ids() -> PackedStringArray:
	return GameData.division_ids


func template_name(tid: String) -> String:
	return String(GameData.divisions.get(tid, {}).get("name", tid))


func manpower_cost(tid: String) -> int:
	return int(GameData.divisions.get(tid, {}).get("manpower", 0))


## Equipment id -> units needed (ints).
func equipment_cost(tid: String) -> Dictionary:
	var out: Dictionary = {}
	var eq: Dictionary = GameData.divisions.get(tid, {}).get("equipment", {})
	for k in eq:
		out[String(k)] = int(eq[k])
	return out


func recruit_days(tid: String) -> int:
	return int(GameData.divisions.get(tid, {}).get("recruit_days", 30))


## "10,000 men, 100 Inf Eq, 30 days"
func cost_text(tid: String) -> String:
	var parts: PackedStringArray = ["%s men" % UIStyle.fmt_int(manpower_cost(tid))]
	var eq := equipment_cost(tid)
	for k in eq:
		parts.append("%d %s" % [int(eq[k]), String(GameData.equipment.get(k, {}).get("short", k))])
	parts.append("%d days" % recruit_days(tid))
	return ", ".join(parts)


func is_unlocked(nid: String, tid: String) -> bool:
	var n: NationState = GameState.nation(nid)
	return n != null and TechEffects.is_division_unlocked(tid, n.researched)


## Land province owned and controlled by [param nid].
func is_valid_deploy(nid: String, pid: String) -> bool:
	if pid == "" or GameState.province(pid) == null or GameData.is_naval(pid):
		return false
	var ps: ProvinceState = GameState.province(pid)
	return ps.owner == nid and ps.controller == nid


func deploy_provinces(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not GameState.active:
		return out
	for pid in GameData.province_ids:
		if is_valid_deploy(nid, pid):
			out.append(pid)
	return out


## Capital if valid, else the first valid deploy province, else "".
func default_deploy_province(nid: String) -> String:
	var cap := String(GameData.nation(nid).get("capital", ""))
	if is_valid_deploy(nid, cap):
		return cap
	var all := deploy_provinces(nid)
	return all[0] if not all.is_empty() else ""


## How many divisions of [param tid] the current stock pays for.
func affordable_count(nid: String, tid: String) -> int:
	var n: NationState = GameState.nation(nid)
	if n == null or not GameData.divisions.has(tid):
		return 0
	var best := 1000000
	var mp := manpower_cost(tid)
	if mp > 0:
		best = mini(best, n.manpower / mp)
	var eq := equipment_cost(tid)
	for k in eq:
		if int(eq[k]) > 0:
			best = mini(best, int(floor(float(n.stockpile.get(k, 0.0)) / float(eq[k]) + 0.000001)))
	return best


## "" if [param nid] may recruit [param tid] in [param pid] now, else the reason.
func recruit_error(nid: String, tid: String, pid: String) -> String:
	if not GameState.active:
		return "No game running"
	var n: NationState = GameState.nation(nid)
	if n == null:
		return "Unknown nation"
	if n.capitulated:
		return "Nation has capitulated"
	if not GameData.divisions.has(tid):
		return "Unknown division type"
	if not TechEffects.is_division_unlocked(tid, n.researched):
		var req := String(GameData.divisions[tid].get("required_tech", ""))
		return "Requires %s" % String(GameData.techs.get(req, {}).get("name", req))
	if pid == "" or GameState.province(pid) == null:
		return "No deployment province"
	if GameData.is_naval(pid):
		return "Cannot deploy in a naval zone"
	if not is_valid_deploy(nid, pid):
		return "%s is not under your control" % GameData.province_name(pid)
	if n.manpower < manpower_cost(tid):
		return "Not enough manpower (%s / %s)" % [UIStyle.fmt_int(n.manpower), UIStyle.fmt_int(manpower_cost(tid))]
	var eq := equipment_cost(tid)
	for k in eq:
		var have := float(n.stockpile.get(k, 0.0))
		if have + 0.000001 < float(eq[k]):
			return "Not enough %s (%d / %d)" % [String(GameData.equipment.get(k, {}).get("name", k)), int(floor(have)), int(eq[k])]
	return ""


func can_recruit(nid: String, tid: String, pid: String) -> bool:
	return recruit_error(nid, tid, pid) == ""


## Pay the cost and queue one division. Returns false (and changes nothing) if refused.
func recruit(nid: String, tid: String, pid: String) -> bool:
	if recruit_error(nid, tid, pid) != "":
		return false
	var n: NationState = GameState.nation(nid)
	n.manpower -= manpower_cost(tid)
	var eq := equipment_cost(tid)
	for k in eq:
		n.stockpile[k] = float(n.stockpile.get(k, 0.0)) - float(eq[k])
	n.recruit_queue.append({"template": tid, "province": pid, "days_left": recruit_days(tid)})
	EventBus.nation_changed.emit(nid)
	return true


## Remove queue entry [param index] and refund its full cost.
func cancel_recruit(nid: String, index: int) -> bool:
	var n: NationState = GameState.nation(nid)
	if n == null or index < 0 or index >= n.recruit_queue.size():
		return false
	var item: Dictionary = n.recruit_queue[index]
	n.recruit_queue.remove_at(index)
	var tid := String(item.template)
	n.manpower += manpower_cost(tid)
	var eq := equipment_cost(tid)
	for k in eq:
		n.stockpile[k] = float(n.stockpile.get(k, 0.0)) + float(eq[k])
	EventBus.nation_changed.emit(nid)
	return true


## Copies of the queue entries plus "total_days" and "progress" (0..1).
func queue(nid: String) -> Array:
	var out: Array = []
	var n: NationState = GameState.nation(nid)
	if n == null:
		return out
	for item: Dictionary in n.recruit_queue:
		var e := item.duplicate()
		var total := maxi(1, recruit_days(String(item.template)))
		e["total_days"] = total
		e["progress"] = clampf(1.0 - float(item.days_left) / float(total), 0.0, 1.0)
		out.append(e)
	return out


## Divisions of [param nid] in training per template.
func queued_count(nid: String, tid: String = "") -> int:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return 0
	var c := 0
	for item: Dictionary in n.recruit_queue:
		if tid == "" or String(item.template) == tid:
			c += 1
	return c
