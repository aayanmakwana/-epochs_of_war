class_name NationState
extends RefCounted
## Mutable runtime state of one nation. Static data (name, color, flag,
## capital ...) stays in GameData.nations.

const STOCKPILE_KEYS: PackedStringArray = ["infantry_equipment", "armor", "artillery", "oil", "steel"]

var id: String = ""
var is_player: bool = false
var manpower: int = 0
## Key -> float. Keys: STOCKPILE_KEYS.
var stockpile: Dictionary = {}
## Equipment id -> number of factories assigned. (step 6)
var factory_allocation: Dictionary = {}
## Equipment id -> fractional production progress carried between days. (step 6)
var production_progress: Dictionary = {}
## Researched tech ids. (step 7)
var researched: Array[String] = []
var current_research: String = ""
## Days of research done on current_research. (step 7)
var research_progress: float = 0.0
## Recruitment queue: Array of {"template": String, "province": String, "days_left": int}. (step 8)
var recruit_queue: Array = []
## Diplomacy (step 13). Lists of nation ids.
var at_war_with: Array[String] = []
var non_aggression: Array[String] = []
## Nations that grant this nation military access.
var military_access: Array[String] = []
## Target nation id -> days left until the war goal is ready (0 = ready).
var war_goals: Dictionary = {}
var capitulated: bool = false
## End screen statistics (step 19).
var stats: Dictionary = {"provinces_conquered": 0, "battles_won": 0, "battles_lost": 0, "divisions_lost": 0}


func is_at_war_with(other: String) -> bool:
	return at_war_with.has(other)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"is_player": is_player,
		"manpower": manpower,
		"stockpile": stockpile.duplicate(),
		"factory_allocation": factory_allocation.duplicate(),
		"production_progress": production_progress.duplicate(),
		"researched": Array(researched),
		"current_research": current_research,
		"research_progress": research_progress,
		"recruit_queue": recruit_queue.duplicate(true),
		"at_war_with": Array(at_war_with),
		"non_aggression": Array(non_aggression),
		"military_access": Array(military_access),
		"war_goals": war_goals.duplicate(),
		"capitulated": capitulated,
		"stats": stats.duplicate(),
	}


static func from_dict(d: Dictionary) -> NationState:
	var n := NationState.new()
	n.id = String(d.get("id", ""))
	n.is_player = bool(d.get("is_player", false))
	n.manpower = int(d.get("manpower", 0))
	n.stockpile = {}
	var sp: Dictionary = d.get("stockpile", {})
	for k in STOCKPILE_KEYS:
		n.stockpile[k] = float(sp.get(k, 0.0))
	n.factory_allocation = {}
	var fa: Dictionary = d.get("factory_allocation", {})
	for k in fa:
		n.factory_allocation[String(k)] = int(fa[k])
	n.production_progress = {}
	var pp: Dictionary = d.get("production_progress", {})
	for k in pp:
		n.production_progress[String(k)] = float(pp[k])
	n.researched = _strings(d.get("researched", []))
	n.current_research = String(d.get("current_research", ""))
	n.research_progress = float(d.get("research_progress", 0.0))
	n.recruit_queue = []
	for item: Dictionary in d.get("recruit_queue", []):
		n.recruit_queue.append({
			"template": String(item.get("template", "")),
			"province": String(item.get("province", "")),
			"days_left": int(item.get("days_left", 0)),
		})
	n.at_war_with = _strings(d.get("at_war_with", []))
	n.non_aggression = _strings(d.get("non_aggression", []))
	n.military_access = _strings(d.get("military_access", []))
	n.war_goals = {}
	var wg: Dictionary = d.get("war_goals", {})
	for k in wg:
		n.war_goals[String(k)] = int(wg[k])
	n.capitulated = bool(d.get("capitulated", false))
	var st: Dictionary = d.get("stats", {})
	for k in st:
		n.stats[String(k)] = int(st[k])
	return n


static func _strings(arr: Array) -> Array[String]:
	var out: Array[String] = []
	for v in arr:
		out.append(String(v))
	return out
