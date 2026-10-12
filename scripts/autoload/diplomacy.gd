extends Node
## Diplomacy (autoload "Diplomacy", step 13).
##
## Three actions (design doc "Diplomacy (simplified)"):
##   - declare war: needs a completed war goal against the target and no
##     non-aggression pact with it. War goals are fabricated with
##     start_justification(nid, target) and take rules.war_goal_days days.
##   - offer non-aggression pact: accepted if the two are not at war. A pact
##     blocks justification and war declaration between the two (both ways);
##     it can be broken with cancel_pact.
##   - request military access: accepted if the host is not at war with the
##     requester. Access lets the guest move / draw supply through the host's
##     land provinces (Movement.is_passable, Supply).
## State lives in NationState: at_war_with, non_aggression, military_access
## (nations whose territory this nation may enter), war_goals (target -> days
## left, 0 = ready). All saved with the game.
##
## Daily system "diplomacy" (order 5, runs just before EventBus.day_passed):
## war goal countdown and the scripted historical declarations of AI nations
## (rules.scripted_wars: [{date: [y, m, d], attacker, defender}], skipped when
## the attacker is the player). France starts neutral (no wars at start).
## Capitulation on capital capture is left to step 19.

const DAILY_ORDER := 5


func _ready() -> void:
	Simulation.register_daily("diplomacy", run_daily, DAILY_ORDER)


func war_goal_days() -> int:
	return int(GameData.rule("war_goal_days", 30))


func _n(nid: String) -> NationState:
	return GameState.nation(nid)


# --- Queries -----------------------------------------------------------------

func is_at_war(a: String, b: String) -> bool:
	var n := _n(a)
	return n != null and n.is_at_war_with(b)


func has_pact(a: String, b: String) -> bool:
	var na := _n(a)
	var nb := _n(b)
	return (na != null and na.non_aggression.has(b)) or (nb != null and nb.non_aggression.has(a))


## True if [param guest] may enter [param host]'s territory.
func has_access(guest: String, host: String) -> bool:
	var n := _n(guest)
	return n != null and n.military_access.has(host)


func is_justifying(nid: String, target: String) -> bool:
	var n := _n(nid)
	return n != null and n.war_goals.has(target) and int(n.war_goals[target]) > 0


func has_war_goal(nid: String, target: String) -> bool:
	var n := _n(nid)
	return n != null and n.war_goals.has(target) and int(n.war_goals[target]) <= 0


## Days left on the war goal against target (-1 = none).
func war_goal_days_left(nid: String, target: String) -> int:
	var n := _n(nid)
	if n == null or not n.war_goals.has(target):
		return -1
	return int(n.war_goals[target])


func enemies(nid: String) -> PackedStringArray:
	var n := _n(nid)
	return PackedStringArray(n.at_war_with) if n else PackedStringArray()


## Short relation text of [param nid] towards [param other] (UI).
func status_text(nid: String, other: String) -> String:
	var o := _n(other)
	if o == null:
		return "Unknown"
	if o.capitulated:
		return "Capitulated"
	var parts: PackedStringArray = []
	if is_at_war(nid, other):
		parts.append("At war")
	elif has_pact(nid, other):
		parts.append("Non-aggression pact")
	else:
		parts.append("Neutral" if _n(other).at_war_with.is_empty() else "At peace")
	if has_access(nid, other):
		parts.append("you have access")
	if has_access(other, nid):
		parts.append("has access to you")
	var left := war_goal_days_left(nid, other)
	if left > 0:
		parts.append("justifying: %d days" % left)
	elif left == 0:
		parts.append("war goal ready")
	return ", ".join(parts)


func _basic_error(nid: String, target: String) -> String:
	var n := _n(nid)
	var t := _n(target)
	if n == null or t == null:
		return "Unknown nation"
	if nid == target:
		return "Cannot target your own nation"
	if n.capitulated:
		return "Nation has capitulated"
	if t.capitulated:
		return "%s has capitulated" % GameData.nation_name(target)
	return ""


# --- War goals ------------------------------------------------------------------

func justification_error(nid: String, target: String) -> String:
	var e := _basic_error(nid, target)
	if e != "":
		return e
	if is_at_war(nid, target):
		return "Already at war with %s" % GameData.nation_name(target)
	if has_pact(nid, target):
		return "Non-aggression pact with %s" % GameData.nation_name(target)
	if is_justifying(nid, target):
		return "Already justifying a war goal"
	if has_war_goal(nid, target):
		return "War goal already ready"
	return ""


func can_justify(nid: String, target: String) -> bool:
	return justification_error(nid, target) == ""


## Start fabricating a war goal against [param target] (war_goal_days days).
func start_justification(nid: String, target: String) -> bool:
	if not can_justify(nid, target):
		return false
	_n(nid).war_goals[target] = war_goal_days()
	EventBus.nation_changed.emit(nid)
	if nid == GameState.player_nation:
		EventBus.notify.emit("Justifying a war goal against %s (%d days)" % [GameData.nation_name(target), war_goal_days()])
	return true


func cancel_justification(nid: String, target: String) -> bool:
	var n := _n(nid)
	if n == null or not n.war_goals.has(target):
		return false
	n.war_goals.erase(target)
	EventBus.nation_changed.emit(nid)
	return true


# --- War ------------------------------------------------------------------------

func declare_war_error(nid: String, target: String) -> String:
	var e := _basic_error(nid, target)
	if e != "":
		return e
	if is_at_war(nid, target):
		return "Already at war with %s" % GameData.nation_name(target)
	if has_pact(nid, target):
		return "Non-aggression pact with %s" % GameData.nation_name(target)
	if is_justifying(nid, target):
		return "War goal not ready (%d days left)" % war_goal_days_left(nid, target)
	if not has_war_goal(nid, target):
		return "Needs a war goal (justify first)"
	return ""


func can_declare_war(nid: String, target: String) -> bool:
	return declare_war_error(nid, target) == ""


## Declare war (needs a ready war goal and no pact). Returns false if refused.
func declare_war(nid: String, target: String) -> bool:
	if not can_declare_war(nid, target):
		return false
	_start_war(nid, target)
	return true


## Put [param a] and [param b] at war without checks (scripted wars, tests).
func _start_war(a: String, b: String) -> void:
	var na := _n(a)
	var nb := _n(b)
	if not na.at_war_with.has(b):
		na.at_war_with.append(b)
	if not nb.at_war_with.has(a):
		nb.at_war_with.append(a)
	na.war_goals.erase(b)
	nb.war_goals.erase(a)
	na.non_aggression.erase(b)
	nb.non_aggression.erase(a)
	na.military_access.erase(b)
	nb.military_access.erase(a)
	_evacuate(a, b)
	_evacuate(b, a)
	EventBus.war_declared.emit(a, b)
	EventBus.nation_changed.emit(a)
	EventBus.nation_changed.emit(b)
	_recheck()
	if a == GameState.player_nation or b == GameState.player_nation:
		EventBus.notify.emit("%s declares war on %s" % [GameData.nation_name(a), GameData.nation_name(b)])


## Divisions of [param nid] standing in [param host]-controlled provinces
## (through former military access) return to their capital.
func _evacuate(nid: String, host: String) -> void:
	var home := ""
	var rec := get_node_or_null("/root/Recruitment")
	if rec:
		home = rec.default_deploy_province(nid)
	var mv := get_node_or_null("/root/Movement")
	for d: DivisionState in GameState.divisions_of(nid):
		var ps: ProvinceState = GameState.province(d.province)
		if ps == null or ps.controller != host:
			continue
		if mv:
			mv.stop(d.id)
		if home == "":
			continue
		var from := d.province
		d.province = home
		d.origin = home
		d.entrenchment = 0.0
		EventBus.division_moved.emit(d.id, from, home)


func _recheck() -> void:
	for name in ["Supply", "Fog"]:
		var s := get_node_or_null("/root/" + name)
		if s and s.has_method("queue_check"):
			s.queue_check()


# --- Pacts ------------------------------------------------------------------------

func pact_error(nid: String, target: String) -> String:
	var e := _basic_error(nid, target)
	if e != "":
		return e
	if is_at_war(nid, target):
		return "At war with %s" % GameData.nation_name(target)
	if has_pact(nid, target):
		return "Pact already signed"
	return ""


func can_offer_pact(nid: String, target: String) -> bool:
	return pact_error(nid, target) == ""


## Offer a non-aggression pact; accepted if not at war. Cancels war goals
## between the two. Returns true when signed.
func offer_pact(nid: String, target: String) -> bool:
	if not can_offer_pact(nid, target):
		return false
	var na := _n(nid)
	var nb := _n(target)
	na.non_aggression.append(target)
	if not nb.non_aggression.has(nid):
		nb.non_aggression.append(nid)
	na.war_goals.erase(target)
	nb.war_goals.erase(nid)
	EventBus.pact_signed.emit(nid, target)
	EventBus.nation_changed.emit(nid)
	EventBus.nation_changed.emit(target)
	if nid == GameState.player_nation or target == GameState.player_nation:
		EventBus.notify.emit("Non-aggression pact signed with %s" % GameData.nation_name(target if nid == GameState.player_nation else nid))
	return true


func cancel_pact(nid: String, target: String) -> bool:
	if not has_pact(nid, target):
		return false
	_n(nid).non_aggression.erase(target)
	_n(target).non_aggression.erase(nid)
	EventBus.nation_changed.emit(nid)
	EventBus.nation_changed.emit(target)
	return true


# --- Military access ----------------------------------------------------------------

func access_error(nid: String, host: String) -> String:
	var e := _basic_error(nid, host)
	if e != "":
		return e
	if is_at_war(nid, host):
		return "At war with %s" % GameData.nation_name(host)
	if has_access(nid, host):
		return "Access already granted"
	return ""


func can_request_access(nid: String, host: String) -> bool:
	return access_error(nid, host) == ""


## Ask [param host] for military access; accepted if not at war.
func request_access(nid: String, host: String) -> bool:
	if not can_request_access(nid, host):
		return false
	_n(nid).military_access.append(host)
	EventBus.military_access_granted.emit(host, nid)
	EventBus.nation_changed.emit(nid)
	EventBus.nation_changed.emit(host)
	_recheck()
	if nid == GameState.player_nation:
		EventBus.notify.emit("%s grants military access" % GameData.nation_name(host))
	return true


func revoke_access(host: String, guest: String) -> bool:
	if not has_access(guest, host):
		return false
	_n(guest).military_access.erase(host)
	EventBus.nation_changed.emit(guest)
	EventBus.nation_changed.emit(host)
	_recheck()
	return true


# --- Daily tick -------------------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	for nid in GameData.nation_ids:
		var n := _n(nid)
		if n == null or n.capitulated:
			continue
		var targets: Array = n.war_goals.keys()
		targets.sort()
		for t in targets:
			var left := int(n.war_goals[t])
			if left <= 0:
				continue
			n.war_goals[t] = left - 1
			if left - 1 == 0:
				EventBus.nation_changed.emit(nid)
				if nid == GameState.player_nation:
					EventBus.notify.emit("War goal against %s is ready" % GameData.nation_name(t))
	_run_scripted_wars()


func scripted_wars() -> Array:
	return GameData.rule("scripted_wars", [])


func _run_scripted_wars() -> void:
	for w: Dictionary in scripted_wars():
		var dt: Array = w.get("date", [])
		if dt.size() < 3:
			continue
		# ">=" so a save loaded past the date still triggers it once (at war afterwards).
		if GameState.day_index < GameDate.to_index(int(dt[0]), int(dt[1]), int(dt[2])):
			continue
		var a := String(w.get("attacker", ""))
		var b := String(w.get("defender", ""))
		if a == GameState.player_nation or _basic_error(a, b) != "" or is_at_war(a, b):
			continue
		_start_war(a, b)
