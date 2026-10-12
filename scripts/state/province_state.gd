class_name ProvinceState
extends RefCounted
## Mutable runtime state of one province. Static data (name, terrain,
## resources, geometry) stays in GameData.provinces / GameData.geometry.

var id: String = ""
## Legal owner. Changes only on capitulation / peace.
var owner: String = ""
## Who holds it militarily right now (supply, income and fog use this).
var controller: String = ""
var factories: int = 0
var infrastructure: int = 1
## Factories under construction: Array of {"days_left": int}. (step 6)
var factory_queue: Array = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"controller": controller,
		"factories": factories,
		"infrastructure": infrastructure,
		"factory_queue": factory_queue.duplicate(true),
	}


static func from_dict(d: Dictionary) -> ProvinceState:
	var p := ProvinceState.new()
	p.id = String(d.get("id", ""))
	p.owner = String(d.get("owner", ""))
	p.controller = String(d.get("controller", p.owner))
	p.factories = int(d.get("factories", 0))
	p.infrastructure = int(d.get("infrastructure", 1))
	p.factory_queue = []
	for item: Dictionary in d.get("factory_queue", []):
		p.factory_queue.append({"days_left": int(item.get("days_left", 0))})
	return p
