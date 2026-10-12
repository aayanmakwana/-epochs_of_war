class_name TacticalDeployment
extends RefCounted
## Forces and deployment for one tactical battle (step 15). Pure data class.
##
## add_division() splits a strategic division into its 3 tactical units;
## auto_deploy(side) fills the side's deploy zone (front tiles first, artillery
## at the back); place_unit() moves a unit to a deploy tile of its own side
## (swapping with an own unit already there). Units that do not fit stay in
## reserve (pos = TacticalUnit.NO_POS). Steps 16/17 build the turn logic on top.

var map: TacticalMap
var province: String = ""
var attacker: String = ""
var defender: String = ""
var units: Array[TacticalUnit] = []
var _next_id: int = 1


func _init(tactical_map: TacticalMap = null) -> void:
	map = tactical_map


## Add the tactical units of one strategic division. [param unit_types] = the
## template's tactical_units (e.g. ["armor", "armor", "infantry"]);
## [param unit_stats] = GameData.tactical.units. Returns the new units.
func add_division(side: String, nation: String, division_id: int, unit_types: Array,
		unit_stats: Dictionary, hp_fraction: float = 1.0) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	for t in unit_types:
		var u := TacticalUnit.create(_next_id, str(t), unit_stats.get(str(t), {}), side, nation, division_id, hp_fraction)
		_next_id += 1
		units.append(u)
		out.append(u)
	return out


func unit(uid: int) -> TacticalUnit:
	for u in units:
		if u.id == uid:
			return u
	return null


func unit_at(p: Vector2i) -> TacticalUnit:
	for u in units:
		if u.pos == p:
			return u
	return null


func units_of(side: String) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	for u in units:
		if u.side == side:
			out.append(u)
	return out


func reserve(side: String) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	for u in units_of(side):
		if not u.is_deployed() and not u.destroyed and not u.routed:
			out.append(u)
	return out


func is_fully_deployed(side: String) -> bool:
	return reserve(side).is_empty() or free_deploy_tiles(side).is_empty()


func free_deploy_tiles(side: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in map.deploy_tiles(side):
		if unit_at(p) == null:
			out.append(p)
	return out


## Place every unit of [param side] from scratch: non-artillery on the front
## tiles, artillery on the rearmost tiles. Extra units stay in reserve.
func auto_deploy(side: String) -> void:
	for u in units_of(side):
		u.pos = TacticalUnit.NO_POS
	var free := map.deploy_tiles(side)
	var front: Array[TacticalUnit] = []
	var back: Array[TacticalUnit] = []
	for u in units_of(side):
		if u.type == "artillery":
			back.append(u)
		else:
			front.append(u)
	for u in front:
		if free.is_empty():
			break
		u.pos = free.pop_front()
	for u in back:
		if free.is_empty():
			break
		u.pos = free.pop_back()


## "" if unit [param uid] may be placed on [param p], else the reason.
func placement_error(uid: int, p: Vector2i) -> String:
	var u := unit(uid)
	if u == null:
		return "Unknown unit"
	if not map.in_bounds(p):
		return "Outside the map"
	if not map.is_passable(p):
		return "%s is impassable" % map.tile_name(p)
	if map.is_objective(p):
		return "Cannot deploy on an objective"
	if map.zone_of(p) != u.side:
		return "Outside your deployment zone"
	var other := unit_at(p)
	if other != null and other.side != u.side:
		return "Occupied by the enemy"
	return ""


func can_place(uid: int, p: Vector2i) -> bool:
	return placement_error(uid, p) == ""


## Move unit [param uid] to [param p]; an own unit there swaps into the old spot
## (or goes to reserve if the moved unit came from reserve).
func place_unit(uid: int, p: Vector2i) -> bool:
	if not can_place(uid, p):
		return false
	var u := unit(uid)
	var other := unit_at(p)
	if other != null and other != u:
		other.pos = u.pos
	u.pos = p
	return true


## Send a unit back to reserve.
func withdraw(uid: int) -> void:
	var u := unit(uid)
	if u:
		u.pos = TacticalUnit.NO_POS
