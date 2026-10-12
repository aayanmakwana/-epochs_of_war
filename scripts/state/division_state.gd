class_name DivisionState
extends RefCounted
## Mutable runtime state of one division (steps 8-11 drive it).

var id: int = 0
var template: String = ""
var owner: String = ""
## Province the division is currently in.
var province: String = ""
var hp: float = 0.0
var organization: float = 0.0
## Movement (step 9): remaining path (next province first) and progress
## towards path[0] in [0, 1].
var path: Array[String] = []
var move_progress: float = 0.0
## Defensive entrenchment in [0, 1] (step 10).
var entrenchment: float = 0.0
## Province the division last came from (retreat target, step 10).
var origin: String = ""


func is_moving() -> bool:
	return not path.is_empty()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"template": template,
		"owner": owner,
		"province": province,
		"hp": hp,
		"organization": organization,
		"path": Array(path),
		"move_progress": move_progress,
		"entrenchment": entrenchment,
		"origin": origin,
	}


static func from_dict(d: Dictionary) -> DivisionState:
	var dv := DivisionState.new()
	dv.id = int(d.get("id", 0))
	dv.template = String(d.get("template", ""))
	dv.owner = String(d.get("owner", ""))
	dv.province = String(d.get("province", ""))
	dv.hp = float(d.get("hp", 0.0))
	dv.organization = float(d.get("organization", 0.0))
	dv.path = []
	for p in d.get("path", []):
		dv.path.append(String(p))
	dv.move_progress = float(d.get("move_progress", 0.0))
	dv.entrenchment = float(d.get("entrenchment", 0.0))
	dv.origin = String(d.get("origin", ""))
	return dv
