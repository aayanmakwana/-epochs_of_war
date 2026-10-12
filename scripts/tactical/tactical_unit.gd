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

# --- Per-turn battle state (step 16) ---
## Movement points left this phase (reset to `movement` at the start of the side's phase).
var moves_left: int = 0
## True once the unit used its one action (attack, ability or overwatch) this phase.
var acted: bool = false
## Infantry "dig in": +DIG_IN_DEFENSE defense until the unit moves.
var dug_in: bool = false
## Overwatch: fires at the first enemy that moves within range during the enemy phase.
var overwatch: bool = false
## Destroyed (0 HP) units leave the map (pos = NO_POS) and stay in the list for casualty counts.
var destroyed: bool = false

const DIG_IN_DEFENSE := 2


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


## Deployed and not destroyed: on the battlefield.
func is_active() -> bool:
	return pos != NO_POS and not destroyed and hp > 0


## Base defense including dig in (terrain is applied by TacticalBattle).
func base_defense() -> int:
	return defense + (DIG_IN_DEFENSE if dug_in else 0)


## Reset the per-phase fields at the start of this unit's side's phase.
func begin_phase() -> void:
	moves_left = movement
	acted = false
	overwatch = false


## Map letter: I / A / R.
func letter() -> String:
	match type:
		"armor":
			return "A"
		"artillery":
			return "R"
	return "I"
