class_name TechEffects
extends RefCounted
## Applies the effects listed in data/techs.json. Everything is computed from
## the list of researched tech ids, so there is no hidden mutable state:
## research just appends to NationState.researched.

const DIVISION_STATS: PackedStringArray = ["attack", "defense", "speed", "organization", "hp"]


## Effective stats of a division template for a nation with [param researched].
## Returns {"attack", "defense", "speed", "organization", "hp", "support_attack_bonus"}.
static func division_stats(template_id: String, researched: Array) -> Dictionary:
	var tpl: Dictionary = GameData.divisions.get(template_id, {})
	var mult: Dictionary = {}
	for s in DIVISION_STATS:
		mult[s] = 1.0
	var support_bonus := 0.0
	for tech_id in researched:
		var tech: Dictionary = GameData.techs.get(tech_id, {})
		for e: Dictionary in tech.get("effects", []):
			match String(e.get("type", "")):
				"division_stat":
					var div: String = e.get("division", "")
					var stat: String = e.get("stat", "")
					if (div == "all" or div == template_id) and mult.has(stat):
						mult[stat] += float(e.get("mult", 0.0))
				"support_bonus":
					support_bonus += float(e.get("value", 0.0))
	var out: Dictionary = {}
	for s in DIVISION_STATS:
		out[s] = float(tpl.get(s, 0)) * maxf(0.1, mult[s])
	var base_support := float(tpl.get("support_attack_bonus", 0.0))
	out["support_attack_bonus"] = base_support + (support_bonus if base_support > 0.0 else 0.0)
	return out


## Sum of a global effect value (production_mult, manpower_growth_mult ...).
static func global_value(effect_type: String, researched: Array) -> float:
	var total := 0.0
	for tech_id in researched:
		var tech: Dictionary = GameData.techs.get(tech_id, {})
		for e: Dictionary in tech.get("effects", []):
			if String(e.get("type", "")) == effect_type:
				total += float(e.get("value", 0.0))
	return total


static func production_multiplier(researched: Array) -> float:
	return 1.0 + global_value("production_mult", researched)


static func manpower_growth_multiplier(researched: Array) -> float:
	return 1.0 + global_value("manpower_growth_mult", researched)


## Can a nation with [param researched] recruit [param template_id]?
static func is_division_unlocked(template_id: String, researched: Array) -> bool:
	var tpl: Dictionary = GameData.divisions.get(template_id, {})
	var req: String = tpl.get("required_tech", "")
	return req == "" or researched.has(req)


## Can [param tech_id] be researched next (prerequisite done, not yet researched)?
static func can_research(tech_id: String, researched: Array) -> bool:
	if researched.has(tech_id) or not GameData.techs.has(tech_id):
		return false
	var req: String = GameData.techs[tech_id].get("requires", "")
	return req == "" or researched.has(req)
