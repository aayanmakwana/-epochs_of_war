class_name TacticalUnit
extends RefCounted
## One tactical unit (step 15): infantry squad, armor platoon or artillery
## battery. Each strategic division splits into 3 of these (divisions.json
## "tactical_units"). Pure data, no autoload references.

const NO_POS := Vector2i(-1, -1)

var id: int = 0
var type: String = ""          # infantry | armor | artillery (GameData.tactical.units keys)
var name: String = ""
var side: String = ""          # attacker | defender
var nation: String = ""
var division_id: int = -1      # strategic division it belongs to
var pos: Vector2i = NO_POS     # NO_POS = in reserve (not deployed)
var hp: int = 0
var max_hp: int = 0
var movement: int = 0
var attack_range: int = 1
var attack: int = 0
var defense: int = 0
var ability: String = ""
## Direction the unit last moved (front arc, step 17 flanking). Starts facing the enemy.
var facing: Vector2i = Vector2i.ZERO


## Build from a unit stats dict (GameData.tactical.units[type]). Starting HP is
## scaled by the strategic division's HP fraction (at least 1).
static func create(uid: int, unit_type: String, stats: Dictionary, unit_side: String,
		nation_id: String, div_id: int, hp_fraction: float = 1.0) -> TacticalUnit:
	var u := TacticalUnit.new()
	u.id = uid
	u.type = unit_type
	u.name = str(stats.get("name", unit_type.capitalize()))
	u.side = unit_side
	u.nation = nation_id
	u.division_id = div_id
	u.max_hp = int(stats.get("hp", 10))
	u.hp = clampi(int(round(u.max_hp * clampf(hp_fraction, 0.0, 1.0))), 1, u.max_hp)
	u.movement = int(stats.get("movement", 3))
	u.attack_range = int(stats.get("range", 1))
	u.attack = int(stats.get("attack", 4))
	u.defense = int(stats.get("defense", 5))
	u.ability = str(stats.get("ability", ""))
	u.facing = Vector2i(0, -1) if unit_side == "attacker" else Vector2i(0, 1)
	return u


func is_deployed() -> bool:
	return pos != NO_POS


## Map letter: I / A / R.
func letter() -> String:
	match type:
		"armor":
			return "A"
		"artillery":
			return "R"
	return "I"
