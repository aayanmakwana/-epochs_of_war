extends Node
## Research system (autoload "Research", step 7).
##
## One tech at a time per nation. Runs once per in-game day through Simulation
## ("research", order 20, after production): every non-capitulated nation with a
## current_research adds rules.research_speed days of progress. When progress
## reaches the tech's "days" the tech is appended to NationState.researched,
## current_research is cleared and EventBus.research_completed(nid, tech) +
## nation_changed(nid) are emitted (plus notify(text) for the player).
##
## Effects are not applied here: TechEffects computes stats, unlocks and
## multipliers from NationState.researched, so completing a tech is enough.
##
## Switching to another tech keeps the old tech's progress in
## NationState.research_saved (tech -> days) and resumes it when picked again.
## All state lives in NationState (current_research, research_progress,
## research_saved, researched), so it saves.

const STATUS_RESEARCHED := "researched"
const STATUS_RESEARCHING := "researching"
const STATUS_AVAILABLE := "available"
const STATUS_LOCKED := "locked"

## Days processed (tests / debugging).
var days_processed: int = 0


func _ready() -> void:
	Simulation.register_daily("research", run_daily, 20)


# --- Daily tick ----------------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	days_processed += 1
	for nid in GameData.nation_ids:
		var n: NationState = GameState.nation(nid)
		if n == null or n.capitulated or n.current_research == "":
			continue
		var tid := n.current_research
		if not GameData.techs.has(tid) or n.researched.has(tid):
			# Stale (e.g. edited save): drop it silently.
			n.current_research = ""
			n.research_progress = 0.0
			EventBus.nation_changed.emit(nid)
			continue
		n.research_progress += research_speed(nid)
		if n.research_progress + 0.000001 >= tech_days(tid):
			_complete(n, tid)
		else:
			EventBus.nation_changed.emit(nid)


func _complete(n: NationState, tid: String) -> void:
	n.researched.append(tid)
	n.current_research = ""
	n.research_progress = 0.0
	n.research_saved.erase(tid)
	EventBus.research_completed.emit(n.id, tid)
	EventBus.nation_changed.emit(n.id)
	if n.id == GameState.player_nation:
		EventBus.notify.emit("Research complete: %s" % tech_name(tid))


# --- Queries -------------------------------------------------------------------

func tech_name(tid: String) -> String:
	return String(GameData.techs.get(tid, {}).get("name", tid))


## Days needed to research [param tid] (techs.json "days").
func tech_days(tid: String) -> float:
	return float(GameData.techs.get(tid, {}).get("days", 0))


## Days of progress per in-game day (rules.research_speed, default 1).
func research_speed(_nid: String) -> float:
	return float(GameData.rule("research_speed", 1.0))


func current(nid: String) -> String:
	var n: NationState = GameState.nation(nid)
	return n.current_research if n else ""


func is_researched(nid: String, tid: String) -> bool:
	var n: NationState = GameState.nation(nid)
	return n != null and n.researched.has(tid)


## Days of progress on [param tid] (current or saved partial progress).
func progress_days(nid: String, tid: String) -> float:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return 0.0
	if n.researched.has(tid):
		return tech_days(tid)
	if n.current_research == tid:
		return n.research_progress
	return float(n.research_saved.get(tid, 0.0))


## 0..1 progress on [param tid] (current research when tid is "").
func progress_fraction(nid: String, tid: String = "") -> float:
	if tid == "":
		tid = current(nid)
	if tid == "" or tech_days(tid) <= 0.0:
		return 0.0
	return clampf(progress_days(nid, tid) / tech_days(tid), 0.0, 1.0)


## Whole days until [param tid] (current research when "") would finish.
func days_left(nid: String, tid: String = "") -> int:
	if tid == "":
		tid = current(nid)
	if tid == "":
		return 0
	var remaining := maxf(0.0, tech_days(tid) - progress_days(nid, tid))
	return int(ceil(remaining / maxf(0.0001, research_speed(nid)) - 0.000001))


## STATUS_RESEARCHED | STATUS_RESEARCHING | STATUS_AVAILABLE | STATUS_LOCKED.
func status(nid: String, tid: String) -> String:
	var n: NationState = GameState.nation(nid)
	if n == null:
		return STATUS_LOCKED
	if n.researched.has(tid):
		return STATUS_RESEARCHED
	if n.current_research == tid:
		return STATUS_RESEARCHING
	if TechEffects.can_research(tid, n.researched):
		return STATUS_AVAILABLE
	return STATUS_LOCKED


## "" if [param nid] may start [param tid] now, else the reason.
func research_error(nid: String, tid: String) -> String:
	if not GameState.active:
		return "No game running"
	var n: NationState = GameState.nation(nid)
	if n == null:
		return "Unknown nation"
	if n.capitulated:
		return "Nation has capitulated"
	if not GameData.techs.has(tid):
		return "Unknown technology"
	if n.researched.has(tid):
		return "Already researched"
	if n.current_research == tid:
		return "Already researching"
	var req: String = GameData.techs[tid].get("requires", "")
	if req != "" and not n.researched.has(req):
		return "Requires %s" % tech_name(req)
	return ""


func can_research(nid: String, tid: String) -> bool:
	return research_error(nid, tid) == ""


## Techs [param nid] could start now, branch order then tier.
func available_techs(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for branch in GameData.tech_branches:
		for tid: String in GameData.techs_in_branch(branch):
			if status(nid, tid) == STATUS_AVAILABLE:
				out.append(tid)
	return out


## Researched / total in a branch: {"done", "total"}.
func branch_progress(nid: String, branch: String) -> Dictionary:
	var list := GameData.techs_in_branch(branch)
	var done := 0
	for tid: String in list:
		if is_researched(nid, tid):
			done += 1
	return {"done": done, "total": list.size()}


# --- Actions -------------------------------------------------------------------

## Start researching [param tid]. A tech already in progress is paused and its
## progress kept in research_saved. Returns false (and changes nothing) if not allowed.
func start_research(nid: String, tid: String) -> bool:
	if not can_research(nid, tid):
		return false
	var n: NationState = GameState.nation(nid)
	_shelve_current(n)
	n.current_research = tid
	n.research_progress = float(n.research_saved.get(tid, 0.0))
	n.research_saved.erase(tid)
	EventBus.research_started.emit(nid, tid)
	EventBus.nation_changed.emit(nid)
	return true


## Stop the current research (progress is kept for later). Returns true if something stopped.
func cancel_research(nid: String) -> bool:
	var n: NationState = GameState.nation(nid)
	if n == null or n.current_research == "":
		return false
	_shelve_current(n)
	EventBus.nation_changed.emit(nid)
	return true


func _shelve_current(n: NationState) -> void:
	if n.current_research != "" and n.research_progress > 0.0:
		n.research_saved[n.current_research] = n.research_progress
	n.current_research = ""
	n.research_progress = 0.0
